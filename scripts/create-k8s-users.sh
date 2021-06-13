#!/bin/bash

cd $(dirname $0)

PROMPTS=0

# 
# usage:
#   create_users.sh [-t]
#
# -t: Perform tests to check access rights
#     The tests will fail prior to creating appropriates Roles&Bindings
#
# Without arguments, the script will
# Generate some YAML Manifests for
#   - ClusterRole/Role and ClusterRoleBinding/RoleBindings
#     giving most admin rights to some specific namespaces
#     giving read-only  rights across all       namespaces
#   Note: it will not apply those manifests
#
# For some test users
#   - Generate a Namespace/ServiceAccount
#   - Generate a kubeconfig_user file
#
# Perform tests to check access rights
#

die() { echo "$0: die - $*" >&2; exit 1; }

press() {
    echo; echo $*
    [ $PROMPTS -eq 0 ] && return

    echo "Press <enter>"
    read DUMMY;
    [ "$DUMMY" = "q" ] && exit; 
    [ "$DUMMY" = "Q" ] && exit; 
}

RUN() {
    CMD=$*
    echo "-- $CMD"
    eval $CMD
}

CREATE_CLUSTER_ROLES() {

    cat > clusterrole-pv.yaml <<EOF
#
# ClusterRole pv-cluster allows to perform all PV related actions:
#
# - applies to apiGroup:    default
#     for resource type:  persistentvolumes
#     all operations (verbs)
#
# - applies to apiGroup:    storage.k8s.io
#     for resource type:  storageclasses
#     all operations (verbs)
#

kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: pv-cluster
rules:
- apiGroups: [""]
  resources:
  - persistentvolumes
  verbs:     ["*"]
- apiGroups: ["storage.k8s.io"]
  resources:
  - storageclasses
  verbs:     ["*"]
EOF

    cat > clusterrole-view.yaml <<EOF
#
# ClusterRole view-cluster allows read-only access to most resource types:
#
# - applies to apiGroups:  default, v1, rbac.authorization.k8s.io
#     for resource types:  all
#     operations:          all read-only (get, watch, list)
#
# "" (default) allows to operate on nodes
# "v1" allows namespaces(not needed) and componentstatuses(cs)
# "rbac.authorization.k8s.io" allows role/clusteroles and bindings
#

kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: view-cluster
rules:
- apiGroups: ["*","v1","rbac.authorization.k8s.io"]
  resources: ["*"]
  verbs:     ["get","watch","list"]
EOF
}

CREATE_USER_ROLES() {
    USER=$1; shift
    [ -z "$USER" ] && die "Missing username"

    NAMESPACE=$1; shift
    [ -z "$NAMESPACE" ] && die "Missing namespace"

    cat > role-${NAMESPACE}-edit.yaml <<EOF
#
# Role admin-users will provide full admin rights on the NAMESPACE:
#
# - applies to apiGroups:   default, extensions, apps, networking.k8s.io (not exhaustive)
#     for resource type:    any
#     all operations (verbs)
#
# - applies to apiGroups:   batch
#     for resource type:    jobs, cronjobs
#     all operations (verbs)
#
# Note: addition of networking.k8s.io/v1 only to NAMESPACE to allow ingress rules
#

kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: admin-users
  namespace: $NAMESPACE
rules:
- apiGroups: ["", "extensions", "apps", "networking.k8s.io"]
  resources: ["*"]
  verbs:     ["*"]
- apiGroups: ["batch"]
  resources:
  - jobs
  - cronjobs
  verbs:     ["*"]

---
# Role admin-default will provides admin rights excluding ingress on the default namespace:
#
# Note: still disallowing ingress rules on default namespace
#

kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: admin-default
  namespace: default
rules:
- apiGroups: ["", "extensions", "apps"]
  resources: ["*"]
  verbs:     ["*"]
- apiGroups: ["batch"]
  resources:
  - jobs
  - cronjobs
  verbs:     ["*"]
EOF

    cat > rb-${USER}-${NAMESPACE}-edit.yaml <<EOF
#
#  RoleBinding edit-USER-default gives USER admin-default role on default   namespace:

apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: edit-${USER}-default
  namespace: default
subjects:
- kind: ServiceAccount
  name: ${USER}
  namespace: default
roleRef:
  kind: Role
  name: admin-default
  apiGroup: rbac.authorization.k8s.io

---
#
#  RoleBinding edit-USER-users   gives USER admin-default role on NAMESPACE namespace:

apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: edit-${USER}-users
  namespace: $NAMESPACE
subjects:
- kind: ServiceAccount
  name: ${USER}
  namespace: default
roleRef:
  kind: Role
  name: admin-users
  apiGroup: rbac.authorization.k8s.io

EOF

    cat > crb-${USER}-view.yaml <<EOF
#  
#  ClusterRoleBinding view-USER-cluster gives USER view-cluster ClusterRole on cluster:

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: view-${USER}-cluster
roleRef:
  kind: ClusterRole
  name: view-cluster
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: ${USER}
  namespace: default
EOF


    cat > crb-${USER}-pv.yaml <<EOF
#
#  ClusterRoleBinding pv-USER-cluster gives USER pv-cluster ClusterRole on cluster:

apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: pv-${USER}-cluster
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pv-cluster
subjects:
- kind: ServiceAccount
  name: ${USER}
  namespace: default
EOF
}

CREATE_USER_KUBECONFIG() {
    USER=$1; shift
    [ -z "$USER" ] && die "Missing username"

    NAMESPACE=$1; shift
    [ ! -z "$NAMESPACE" ] && {
        kubectl get ns $NAMESPACE >/dev/null 2>&1 || kubectl create ns $NAMESPACE
    }

    ## CLEAN_USER $USER $NAMESPACE

    kubectl get sa ${USER} >/dev/null 2>&1 || {
        echo; echo "Creating ServiceAcount $USER"
        RUN kubectl create sa ${USER}
    }

    echo; echo "Getting cert/token from ServiceAcount $USER"
    SECRET=$(kubectl get sa ${USER} -o json | jq -r .secrets[].name)
    [ $? -ne 0 ] && die "Failed to get Secret from SeviceAccount"
    kubectl get secret ${SECRET} -o json | jq -r '.data["ca.crt"]' | base64 -d > $HOME/tmp/ca_${USER}.crt

    USER_TOKEN=$(kubectl get secret ${SECRET} -o json | jq -r '.data["token"]' | base64 -d)
    [ $? -ne 0 ] && die "Failed to get user token"
    [ -z "$USER_TOKEN" ] && die "Failed to create user token"

    press "About to get CONTEXT from current kubeconfig file"
    CONTEXT=$( kubectl config current-context )
    echo "CONTEXT='$CONTEXT'"

    CLUSTER_NAME=$( kubectl config get-contexts $CONTEXT | awk '!/^CURRENT / { print $3; }' )
    echo "CLUSTER_NAME='$CLUSTER_NAME'"
    [ -z "$CLUSTER_NAME" ] && die "Failed to get cluster name: $CLUSTER_NAME"

    API_SERVER=$( kubectl config view | grep server: | awk '{ print $2; }' )
    [ -z "$API_SERVER" ] && die "Failed to get api server address $API_SERVER"

    # Set up the config
    USER_CONFIG=kubeconfig_${USER}
    USER_CONTEXT=${USER}-${CLUSTER_NAME#cluster-}
    [ -f ${USER_CONFIG} ] && 
        [ ! -f ${USER_CONFIG}.bak ] && mv $USER_CONFIG ${USER_CONFIG}.bak

    press "About to set-cluster in $USER_CONFIG file"
    KUBECONFIG=$USER_CONFIG kubectl config set-cluster ${CLUSTER_NAME} --embed-certs=true \
        --server=${API_SERVER} --certificate-authority=$HOME/tmp/ca_${USER}.crt

    press "About to set-credentials in $USER_CONFIG file"
    RUN KUBECONFIG=$USER_CONFIG kubectl config set-credentials $USER_CONTEXT --token=${USER_TOKEN}

    press "About to set-context $USER_CONTEXT in $USER_CONFIG file"
    if [ -z "$NAMESPACE" ]; then
        KUBECONFIG=$USER_CONFIG kubectl config set-context $USER_CONTEXT \
            --cluster=${CLUSTER_NAME} --user=$USER_CONTEXT
    else
        KUBECONFIG=$USER_CONFIG kubectl config set-context $USER_CONTEXT \
            --cluster=${CLUSTER_NAME} --namespace=$NAMESPACE --user=$USER_CONTEXT
    fi

    press "About to use-context $USER_CONTEXT in $USER_CONFIG file"
    KUBECONFIG=$USER_CONFIG kubectl config use-context $USER_CONTEXT
}

TEST_USER_KUBECONFIG() {
    USER=$1; shift
    [ -z "$USER" ] && die "Missing username"

    NAMESPACE=$1; shift
    [ ! -z "$NAMESPACE" ] && {
        kubectl get ns $NAMESPACE >/dev/null 2>&1 || kubectl create ns $NAMESPACE
    }

    USER_CONFIG=kubeconfig_${USER}

    #press "About to use-context $USER_CONTEXT in $USER_CONFIG file"
    CMD="KUBECONFIG=$USER_CONFIG kubectl get nodes"
    echo; echo "-- Testing $CMD"; eval $CMD

    CMD="KUBECONFIG=$USER_CONFIG kubectl get -n default pods"
    echo; echo "-- Testing $CMD"; eval $CMD

    CMD="KUBECONFIG=$USER_CONFIG kubectl get -n $NAMESPACE pods"
    echo; echo "-- Testing $CMD"; eval $CMD

    CMD="KUBECONFIG=$USER_CONFIG kubectl create deploy -n $NAMESPACE web-ns      --image mjbright/k8s-demo:1"
    echo; echo "-- Testing $CMD"; eval $CMD

    CMD="KUBECONFIG=$USER_CONFIG kubectl create deploy -n default    web-default --image mjbright/k8s-demo:1"
    echo; echo "-- Testing $CMD"; eval $CMD

}

if [ "$1" = "-t" ]; then
    TEST_USER_KUBECONFIG   user1 ns1
    #TEST_USER_KUBECONFIG   user2 ns2
else
    CREATE_CLUSTER_ROLES

    CREATE_USER_ROLES user1 ns1
    #CREATE_USER_ROLES user2 ns2

    CREATE_USER_KUBECONFIG user1 ns1
    #CREATE_USER_KUBECONFIG user2 ns2

    #TEST_USER_KUBECONFIG   user1 ns1
    #TEST_USER_KUBECONFIG   user2 ns2
fi

exit 0

