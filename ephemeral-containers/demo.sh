#!/bin/bash

cd $(dirname $0)
. ../demos.rc

FLAGS_ENV_FILE=/var/lib/kubelet/kubeadm-flags.env
FEATURE_FLAG="--feature-gates=EphemeralContainers=true"

# FIXED (in ansible setup) 'error: unable to upgrade connection: pod does not exist'
# Need --node-ip flag on kubelet  on master and workers when running with Vagrant/Virtualbox (because of dup MAC addresses problem?)

# SETUP:
# For info about configuring feature-gate:
#    https://www.shogan.co.uk/kubernetes/enabling-and-using-ephemeral-containers-on-kubernetes-1-16/
#
# DEMO:
# 1. Service with problem - would be great an interesting use case
#    - could be several problems and step through them all
#    - what order, fix pods then service or vice-versa?
# 2. Identify problem - extract Pod from service to investigate
#    - change Pod label, observe new Pod created
#    - try exec to Pod - no shell !!
# 3. Now add Ephemeral container

APP_NAME=ectest
DEPLOY_IMAGE="mjbright/ckad-demo:1"

DEPLOY=$APP_NAME
TARGET_CONTAINER_NAME=$APP_NAME

#ALL_NODES="master"
#ALL_NODES=$( echo $( kubectl get nodes --no-headers -o custom-columns=.NAME:.metadata.name ) )
MASTER_NODES=$( echo $( kubectl get nodes --no-headers -o custom-columns=.NAME:.metadata.name -l 'node-role.kubernetes.io/control-plane' ) )
WORKER_NODES=$( echo $( kubectl get nodes --no-headers -o custom-columns=.NAME:.metadata.name -l '!node-role.kubernetes.io/control-plane' ) )
ALL_NODES="$MASTER_NODES $WORKER_NODES"
OTHER_NODES=${ALL_NODES#master }

echo "MASTER_NODES='$MASTER_NODES'"
echo "WORKER_NODES='$WORKER_NODES'"
echo "ALL_NODES='$ALL_NODES'"
echo "OTHER_NODES='$OTHER_NODES'"

#OTHER_NODES="worker1"
CHECK_OTHER_NODES=1

## - Functions: -------------------------------------------------------

die() { echo -e "$0: die - $*" >&2; exit 1; }

GET_POD_IP() {
    local NS=""
    [ "$1" = "-n" ] && { shift; NS="-n $1"; shift; }
    local POD_NAME=$1; shift;

    kubectl get pod $NS $POD_NAME -o custom-columns=IP:status.podIP --no-headers
}

STEP0_SETUP_CONFIG_HELP() {
    cat <<EOF

Instructions on how to enable ephemeral containers

NOTE: tested on Kubernetes v1.19.0
NOTE: config files are specific to use of kubeadm

"You need to set to true the feature gates flag of the Kubernetes control plane elements:
- API Server, Controller Manager, Scheduler and Kubelet.

If your cluster was created using kubeadm, you can find the manifests for the three main
elements in /etc/kubernetes/manifests in the master nodes.
Add the following line into the container command arguments.
    - --feature-gates=EphemeralContainers=true

For the kubelet, check EnvironmentFile entry in /etc/systemd/system/kubelet.service.d/10-kubeadm.conf.
e.g. /var/lib/kubelet/kubeadm-flags.env

On worker & master nodes add '--feature-gates=EphemeralContainers=true' into the KUBELET_KUBEADM_ARGS variable definition,
 e.g. to have:
 In master: /var/lib/kubelet/kubeadm-flags.env:
   KUBELET_KUBEADM_ARGS="--network-plugin=cni --pod-infra-container-image=k8s.gcr.io/pause:3.2 --feature-gates=EphemeralContainers=true"
 In worker1: /var/lib/kubelet/kubeadm-flags.env:
   KUBELET_KUBEADM_ARGS="--network-plugin=cni --pod-infra-container-image=k8s.gcr.io/pause:3.2 --feature-gates=EphemeralContainers=true"

Then reload/restart the kubelet:
   sudo systemctl daemon-reload
   sudo service kubelet restart
and check the feature-gates flag is present on all 4 processes:

EOF
}

CHECK_NODE() {
    ROLE=$1; shift
    NODE=$1; shift

    #ssh -qt $NODE sudo grep -q -- --feature-gates=EphemeralContainers=true $FLAGS_ENV_FILE && return 0
    ssh -qt $NODE sudo grep ^KUBELET_KUBEADM_ARGS $FLAGS_ENV_FILE
    ssh -qt $NODE sudo grep -q -- --feature-gates=EphemeralContainers=true $FLAGS_ENV_FILE && return 0
    local ERROR="$NODE: Feature flags not enabled on kubelet in $FLAGS_ENV_FILE\n"
    ERRORS+=$ERROR
    return 1
}

CHECK_NODE_PROCS() {
    ROLE=$1; shift
    NODE=$1; shift

    if [ "$ROLE" = "control" ]; then
        KUBE_PROCESSES="kube-apiserver kube-controller-manager kube-scheduler /usr/bin/kubelet"
    else
        KUBE_PROCESSES="/usr/bin/kubelet"
    fi

    for KUBE_PROCESS in $KUBE_PROCESSES; do
        ssh $NODE ps -fade |
            grep " $KUBE_PROCESS " | grep -v grep | awk '{ print "    ", $2, $7, $8, $NF; }'
        ssh $NODE ps -fade | grep $KUBE_PROCESS | grep -q -- --feature-gates=EphemeralContainers=true || {
            local FATAL_ERROR="$NODE: Feature flags not set on running $KUBE_PROCESS process"
            echo "    $FATAL_ERROR"
            FATAL_ERRORS+=$FATAL_ERROR"\n"
            return 1
	}
    done
    return 0
}

STEP0_CONFIG_CHECK() {
    # See: https://www.europeclouds.com/blog/debugging-with-ephemeral-containers-in-k8s
    #     - "Enabling ephemeral containers"
    #
    # "You need to set to true the feature gates flag of the Kubernetes control plane elements:
    # - API Server, Controller Manager, Scheduler and Kubelet.
    #
    # If your cluster was created using kubeadm, you can find the manifests for the three main
    # elements in /etc/kubernetes/manifests in the master nodes.
    # Add the following line into the container command arguments.
    #     - --feature-gates=EphemeralContainers=true
    #
    # For the kubelet, check EnvironmentFile entry in /etc/systemd/system/kubelet.service.d/10-kubeadm.conf.
    # e.g. /var/lib/kubelet/kubeadm-flags.env
    #
    # On worker & master nodes add '--feature-gates=EphemeralContainers=true' into the KUBELET_KUBEADM_ARGS variable definition,
    #  e.g. to have:
    #  In master: /var/lib/kubelet/kubeadm-flags.env:
    #    KUBELET_KUBEADM_ARGS="--network-plugin=cni --pod-infra-container-image=k8s.gcr.io/pause:3.2 --feature-gates=EphemeralContainers=true"
    #  In worker1: /var/lib/kubelet/kubeadm-flags.env:
    #    KUBELET_KUBEADM_ARGS="--network-plugin=cni --pod-infra-container-image=k8s.gcr.io/pause:3.2 --feature-gates=EphemeralContainers=true"
    #
    # Then reload/restart the kubelet:
    #    sudo systemctl daemon-reload
    #    sudo service kubelet restart
    # and check the feature-gates flag is present on all 4 processes:
    # 

    # ps -fade | grep kube-apiserver | grep -q -- --feature-gates=EphemeralContainers=true ||
    #     echo "Feature flags not set on kube-apiserver"
    # ps -fade | grep kube-controller-manager | grep -q -- --feature-gates=EphemeralContainers=true ||
    #     echo "Feature flags not set on kube-controller-manager"
    # ps -fade | grep kube-scheduler | grep -q -- --feature-gates=EphemeralContainers=true ||
    #     echo "Feature flags not set on kube-scheduler"
    # sudo service kubelet restart
    # ps -fade | grep kubelet | grep -q -- --feature-gates=EphemeralContainers=true ||
    #     echo "Feature flags not set on kubelet"

    SECTION1 "Checking EphemeralContainers feature-gates flags on all nodes"

    ERRORS=""
    FATAL_ERRORS=""

    if [ $CHECK_OTHER_NODES -ne 0 ]; then
        ROLE="control"
        for NODE in $MASTER_NODES; do
            echo; echo "- Checking configuration on ${NODE} ..."
            CHECK_NODE $ROLE $NODE
            CHECK_NODE_PROCS $ROLE $NODE
        done
        ROLE="worker"
        for NODE in $WORKER_NODES; do
            echo; echo "- Checking configuration on ${NODE} ..."
            CHECK_NODE $ROLE $NODE
            CHECK_NODE_PROCS $ROLE $NODE
        done
    fi

    [ ! -z "$FATAL_ERRORS" ] && {
        echo
        STEP0_SETUP_CONFIG_HELP
        echo
	die "Errors seen in configuration checks:\n$(echo $FATAL_ERRORS | sed 's/^/    /')"
    }

    #ps -fade | grep kube-apiserver | grep -q -- --feature-gates=EphemeralContainers=true          || die "Feature flags not set on kube-apiserver"
    #ps -fade | grep kube-controller-manager | grep -q -- --feature-gates=EphemeralContainers=true || die "Feature flags not set on kube-controller-manager"
    #ps -fade | grep kube-scheduler | grep -q -- --feature-gates=EphemeralContainers=true          || die "Feature flags not set on kube-scheduler"
    #ps -fade | grep kubelet | grep -q -- --feature-gates=EphemeralContainers=true                 || die "Feature flags not set on kubelet"
}

STEP1_DEPLOY_PROBLEM_CASE() {
    CURRENT_FILE="autogen-deploy_${DEPLOY}.yaml"
    cat << EOF > $CURRENT_FILE
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: $APP_NAME
  name: $APP_NAME
spec:
  replicas: 10
  selector:
    matchLabels:
      app: $APP_NAME
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      containers:
      - image: $DEPLOY_IMAGE
        imagePullPolicy: IfNotPresent
        name: $TARGET_CONTAINER_NAME
EOF

    kubectl get deploy $DEPLOY --no-headers 2>/dev/null | grep -q "^$DEPLOY " &&
        RUN kubectl delete -f $CURRENT_FILE
    while kubectl get deploy $DEPLOY --no-headers 2>/dev/null | grep -q "^$DEPLOY "; do
	echo "Waiting for deploy/$DEPLOY to terminate"
	sleep 2
    done
    RUN kubectl create -f $CURRENT_FILE

    echo "TODO: create problem with deployment"
}

STEP2_EXTRACT_A_POD() {
    CURRENT_POD=$(kubectl get pods -l app=$DEPLOY --no-headers | awk '{ print $1; exit(0); }')
    echo "Selected Pod name=$CURRENT_POD"
    POD_IP=""
    while [ -z "$POD_IP" ]; do
        echo "Waiting for Pod to be scheduled/receive IP ..."
        POD_IP=$(GET_POD_IP $CURRENT_POD)
	[ "$POD_IP" = "<none>" ] && POD_IP=""
	sleep 2
    done
    echo "Pod IP for $CURRENT_POD = $POD_IP"

    echo "Before change:"
    RUN kubectl get pods --show-labels
        RUN curl $POD_IP
        RUN kubectl label pod $CURRENT_POD app=debug-${DEPLOY} --overwrite

    sleep 2
    echo; echo "Single Pod has been isolated by changing it's label:"
    kubectl get pods -o wide --show-labels -l "app!=$APP_NAME"
    RUN kubectl get pods --show-labels

    RUN kubectl exec -it $CURRENT_POD -- /bin/sh

    RUN kubectl describe pod $CURRENT_POD
}

OLD_STEP3_EPHEMERAL_CONTAINER() {
    # e.g. https://medium.com/01001101/ephemeral-containers-the-future-of-kubernetes-workload-debugging-c5b7ded3019f
    # e.g. https://www.shogan.co.uk/kubernetes/enabling-and-using-ephemeral-containers-on-kubernetes-1-16/

    echo "Note: current containers ..."
    RUN kubectl describe pod $CURRENT_POD

    CURRENT_FILE="ephemeral-diagnostic-container.json"
cat << EOF > $CURRENT_FILE
{
    "apiVersion": "v1",
    "kind": "EphemeralContainers",
    "metadata": {
            "name": "${DEPLOY}"
    },
    "ephemeralContainers": [{
        "command": [
            "bash"
        ],
        "image": "alpine",
        "imagePullPolicy": "Always",
        "name": "diagtools",
        "stdin": true,
        "tty": true,
        "terminationMessagePolicy": "File"
    }]
}
EOF

    # RUN kubectl create -f $CURRENT_FILE
    kubectl replace --raw /api/v1/namespaces/default/pods/$CURRENT_POD/ephemeralcontainers -f $CURRENT_FILE

    echo "Note: new ephemeral container ..."
    RUN kubectl describe pod $CURRENT_POD
}

STEP3_EPHEMERAL_CONTAINER() {
    # https://www.europeclouds.com/blog/debugging-with-ephemeral-containers-in-k8s
    #    kubectl alpha debug -it example --image=busybox --target=example # <- target=container name within Pod

    echo "Note: current containers ..."
    echo "==> try busybox"
    echo "==> try image stuffed with tools : contrast container size"
    echo "==> try image stuffed with kubectl + krew plugins : contrast container size"
    RUN kubectl describe pod $CURRENT_POD

    #RUN kubectl alpha debug -it $CURRENT_POD --image=busybox --target=$TARGET_CONTAINER_NAME
    RUN kubectl debug -it $CURRENT_POD --image=alpine:latest --target=$TARGET_CONTAINER_NAME

    RUN kubectl describe pod $CURRENT_POD

    RUN kubectl exec -it $CURRENT_POD -- /bin/sh
}

## - Args: ------------------------------------------------------------

## - Main: ------------------------------------------------------------

# 1. Service with problem - would be great an interesting use case
#    - could be several problems and step through them all
#    - what order, fix pods then service or vice-versa?
# 2. Identify problem - extract Pod from service to investigate
#    - change Pod label, observe new Pod created
#    - try exec to Pod - no shell !!
# 3. Now add Ephemeral container

SECTION1 "'Ephemeral containers' demo script"

ERRORS=""
#[ $CHECK_OTHER_NODES -ne 0 ] && for OTHER_NODE in $OTHER_NODES; do \
[ $CHECK_OTHER_NODES -ne 0 ] && for OTHER_NODE in $ALL_NODES; do \
    echo "Checking ssh connectivity 'master->$OTHER_NODE'"; ssh $OTHER_NODE uptime || ERRORS+="Cannot connect to $OTHER_NODE from master\n"; done ; \
        [ ! -z "$ERRORS" ] && die "ssh connectivity errors:\n$ERRORS"

STEP0_CONFIG_CHECK
STEP1_DEPLOY_PROBLEM_CASE
STEP2_EXTRACT_A_POD
STEP3_EPHEMERAL_CONTAINER

