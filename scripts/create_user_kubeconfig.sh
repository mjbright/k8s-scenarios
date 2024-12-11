#!/bin/bash

# Based on https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/#normal-user
#
# Creates a new user/kubeconfig - does not create/bind any roles to user
#
# Example usage:
#   $0 user1 [<op-file>]
#   $0 user2 [<op-file>]
#

TMP_DIR=~/tmp/kubeconfig.user$$
mkdir -p $TMP_DIR/
cd       $TMP_DIR/

which jq || sudo apt-get install -y jq

## -- Func: ------------------------------------------------------------------------------

die() { echo "$0: die - $*" >&2; exit 1; }

DESTROY() {
   for USER_NAME in $*; do
       kubectl get CertificateSigningRequest/${USER_NAME}-csr 2> /dev/null | grep -q csr &&
         kubectl delete CertificateSigningRequest/${USER_NAME}-csr
   done
}

GET_CONTEXT_INFO() {
    local CURRENT_CONTEXT=$( kubectl config current-context )
    echo "CURRENT_CONTEXT=$CURRENT_CONTEXT"
    local CLUSTER=$( kubectl config view -o jsonpath="{.contexts[?(@.name == \"$CURRENT_CONTEXT\")].context.cluster}" )
    echo "CLUSTER=$CLUSTER"

    CLUSTER_ADDR=$( kubectl config view -o jsonpath="{.clusters[?(@.name == \"$CLUSTER\")].cluster.server}" )
    echo "CLUSTER_ADDR=$CLUSTER_ADDR"
}

CREATE_KUBECONFIG() {
    USER_NAME=$1; shift
    GROUP=$1;     shift

    openssl genrsa -out ${USER_NAME}.key 2048 || die "Failed genrsa"

    #openssl req -new -key ${USER_NAME}.key -out ${USER_NAME}.csr -subj "/CN=${USER_NAME}/O=system:masters" || die "Failed req -new -key"
    #openssl req -new -key ${USER_NAME}.key -out ${USER_NAME}.csr -subj "/CN=${USER_NAME}/O=usergroup" || die "Failed req -new -key"
    openssl req -new -key ${USER_NAME}.key -out ${USER_NAME}.csr -subj "/CN=${USER_NAME}/O=${GROUP}" || die "Failed req -new -key"
    #openssl req -new -key ${USER_NAME}.key -out ${USER_NAME}.csr || die "Failed req -new -key"

    cat ${USER_NAME}.csr | base64 -w0
    openssl req -in ${USER_NAME}.csr -noout -text || die "Failed req in"

    cat << EOF > signing-request.yaml 
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USER_NAME}-csr
spec:
  #signerName: "labs.com/lab-student"
  signerName: kubernetes.io/kube-apiserver-client
  groups:
  - system:authenticated
  request: $(cat ${USER_NAME}.csr | base64 | tr -d '\n')
  usages:
  #- digital signature
  #- key encipherment
  #- server auth
  - client auth
EOF
  #expirationSeconds: 86400  # one day

    kubectl create -f signing-request.yaml  || die "Failed create signing-request"
    kubectl get csr

    kubectl certificate approve ${USER_NAME}-csr || die "Failed certificate approve"
    kubectl get csr

    USER_CERT=${USER_NAME}.crt
    kubectl get csr ${USER_NAME}-csr -o jsonpath='{.status.certificate}' | base64 -d > $USER_CERT
    [ ! -s "${USER_CERT}" ] && die "Failed to get user certificate to $USER_CERT"
    ls -al ${USER_CERT}
    cat ${USER_CERT}

    kubectl get cm  kube-root-ca.crt -o json | jq -r '.data."ca.crt"' > ca.crt ||
        die "Failed to get ca.crt"

    CLIENT_CA_CERT=$(cat ${USER_NAME}.crt | base64 -w0)
    CLIENT_KEY_DATA=$(cat ${USER_NAME}.key | base64 -w0)

    cat <<EOF > kubeconfig.${USER_NAME}
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $(cat ca.crt | base64 -w0)
    server: ${CLUSTER_ADDR}
  name: k8s
contexts:
- context:
    cluster: k8s
    user: ${USER_NAME}
  name: k8s
current-context: k8s
kind: Config
preferences: {}
users:
- name: ${USER_NAME}
  user:
    client-certificate-data: $CLIENT_CA_CERT
    client-key-data: $CLIENT_KEY_DATA
EOF

    #ls -al $PWD/kubeconfig.${USER_NAME}
    if [ -z "$OP_FILE" ]; then
        OP_FILE=$PWD/kubeconfig.${USER_NAME}
    else
        cp -a $PWD/kubeconfig.${USER_NAME} $OP_FILE
    fi

    echo; echo "---- Temp files:"
    ls -al $TMP_DIR/
    echo; echo "---- User Kubeconfig file:"
    ls -al $OP_FILE
}

## -- Args: ------------------------------------------------------------------------------

GROUP=""
OP_FILE=""
NEW_USER=$1; shift

[ "$1" = "-g" ] && { shift; GROUP=$1; shift; }
[ ! -z "$1"     ] && OP_FILE=$1
[ -z "$OP_FILE" ] && OP_FILE=~/.kube/config.${NEW_USER}

## -- Main: ------------------------------------------------------------------------------

DESTROY $NEW_USER

GET_CONTEXT_INFO
[ -z "$CLUSTER_ADDR" ] && die "Failed to set CLUSTER_ADDR"

CREATE_KUBECONFIG $NEW_USER $GROUP

