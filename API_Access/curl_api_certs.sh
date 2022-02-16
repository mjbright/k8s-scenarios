#!/bin/bash

# Getting API_URL:
#   See https://kubernetes.io/docs/tasks/access-application-cluster/access-cluster/#without-kubectl-proxy-post-v13x

#  Assumes first server: match is good !
API_URL=$(grep -m 1 server: .kube/config  | awk '{ print $2; }')

#export CLUSTER_NAME="some_server_name"
# Point to the API server referring the cluster name
#APISERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$CLUSTER_NAME\")].cluster.server}")

COLOURS() {
    BLACK='\e[00;30m';    B_BLACK='\e[01;30m';    BG_BLACK='\e[07;30m'
    WHITE='\e[00;37m';    B_WHITE='\e[01;37m';    BG_WHITE='\e[07;37m'
    RED='\e[00;31m';      B_RED='\e[01;31m';      BG_RED='\e[07;31m'
    GREEN='\e[00;32m';    B_GREEN='\e[01;32m'     BG_GREEN='\e[07;32m'
    YELLOW='\e[00;33m';   B_YELLOW='\e[01;33m'    BG_YELLOW='\e[07;33m'
    BLUE='\e[00;34m'      B_BLUE='\e[01;34m'      BG_BLUE='\e[07;34m'
    MAGENTA='\e[00;35m'   B_MAGENTA='\e[01;35m'   BG_MAGENTA='\e[07;35m'
    CYAN='\e[00;36m'      B_CYAN='\e[01;36m'      BG_CYAN='\e[07;36m'

    NORMAL='\e[00m'
}

#COLOURS; echo -e "${RED}HELLO${NORMAL}"; exit

RUN() {
    echo -e "${YELLOW}-- $*${NORMAL}" >&2
    eval $*
}

CMDPRESS() {
    PRESS "${YELLOW}$*${NORMAL}"
}

CPRESS() {
    PRESS "${GREEN}$*${NORMAL}"
}

PRESS() {
    local DUMMY

    [ ! -z "$1" ] && echo -e "$*"
    echo "Press <enter>"
    read DUMMY

    [ "$DUMMY" = "q" ] && exit 0
    [ "$DUMMY" = "Q" ] && exit 0
}

#HL "GREEN" "$GREEN"
HL() {
    # TODO:
    MATCH=$1; shift
    COLOUR=$1; shift

    #sed
}

TRUNCATE_CHARS() {
    N=$1
    [ -z "$1" ] && N=250
    cut -c 1-$N | sed 's/$/ .../'
}

TRUNCATE_LINES() {
    N=$1
    [ -z "$1" ] && N=250
    head -$N
    echo "..."
}

KUBECTL_GET_VERBOSE() {
    echo; CPRESS "--------- kubectl get in verbose mode:"

    echo; echo "kubectl get nodes (showing json request/response):"
    CMDPRESS "-- kubectl -v 10 get nodes | grep ' GET '"
    kubectl -v 10 get nodes |& grep -E "(Response Body| GET )" | grep -viE "ApiResourceList|Service Unavailable|/apis/" | TRUNCATE_CHARS 250

    echo; echo "kubectl get pods (showing json request/response):"
    CMDPRESS "-- kubectl -v 10 get pods | grep ' GET '"
    kubectl -v 10 get pods |& grep -E "(Response Body| GET )" | grep -vi "Service Unavailable" | TRUNCATE_CHARS 250

    echo; echo "kubectl get -A pods (showing json request/response):"
    CMDPRESS "-- kubectl -v 10 get -A pods | grep ' GET '"
    kubectl -v 10 get -A pods |& grep -E "(Response Body| GET )" | grep -vi "Service Unavailable" | TRUNCATE_CHARS 250
}

__KUBECTL_RAW() {
    RUN kubectl get --raw $1
}

KUBECTL_RAW() {
    echo; CPRESS "--------- kubectl get --raw <URL>:"

    #https://10.3.0.94:6443/api/v1/nodes?limit=500
    #https://10.3.0.94:6443/api/v1/namespaces/default/pods?limit=500
    #https://10.3.0.94:6443/api/v1/pods?limit=500

    echo
    __KUBECTL_RAW /api/v1/nodes?limit=500 | TRUNCATE_CHARS 250
    echo
    __KUBECTL_RAW /api/v1/namespaces/default/pods?limit=500 | TRUNCATE_CHARS 250
    echo
    __KUBECTL_RAW /api/v1/pods?limit=500 | TRUNCATE_CHARS 250
}

CURL_CERTS() {
    echo; CPRESS "--------- curl access to API using certificates:"

    echo; echo "-- Extracting certificates from kube config file:"
    #set -x
    RUN "grep certificate-authority-data:  ~/.kube/config | awk '{ print \$2; }' | base64 -d - > cacert.pem"
    RUN "grep client-certificate-data:     ~/.kube/config | awk '{ print \$2; }' | base64 -d - > cert_admin.pem"
    RUN "grep client-key-data:             ~/.kube/config | awk '{ print \$2; }' | base64 -d - > key_admin.pem"
    #set +x

    echo; PRESS "-- Accessing API using using certificates extracted from kube config file:"

    RUN curl -s --cacert ./cacert.pem --cert ./cert_admin.pem --key ./key_admin.pem $API_URL/api/v1/nodes?limit=500 | TRUNCATE_LINES 5
    echo
    RUN curl -s --cacert ./cacert.pem --cert ./cert_admin.pem --key ./key_admin.pem $API_URL/api/v1/namespaces/default/pods?limit=500 | TRUNCATE_LINES 5
    echo
    RUN curl -s --cacert ./cacert.pem --cert ./cert_admin.pem --key ./key_admin.pem $API_URL/api/v1/pods?limit=500 | TRUNCATE_LINES 5
}

KUBECTL_PROXY() {
    echo; CPRESS "--------- ... and finally THE SIMPLE *curl* WAY - using kubectl proxy:"
    kill -9 $( ps -fade | grep kubectl | grep -v grep | awk '{ print $2; }' ) 2>/dev/null

    RUN "kubectl proxy &"

    # Wait for proxy to be avaliable:
    while ! netstat -an | grep ":8001 .* LISTEN "; do sleep 1; done

    RUN      curl -s http://localhost:8001/api/v1/pods | TRUNCATE_LINES 10

    kill -9 $( ps -fade | grep kubectl | grep -v grep | awk '{ print $2; }' ) 2>/dev/null
}

#APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

COLOURS

PRESS "Demonstrating accessing the Kubernetes API by different methods"


CURL_TOKEN() {
    echo; CPRESS "--------- curl access to API using bearer token:"

    echo; echo "-- Obtaining API bearer token from 'default' ServiceAccount of the current namespace:"
    CMDPRESS "kubectl get serviceaccount default -o jsonpath='{.secrets[0].name}'"
    SECRET_NAME=$(kubectl get serviceaccount default -o jsonpath='{.secrets[0].name}')
    echo $SECRET_NAME

    #TOKEN=$(kubectl get secret $SECRET_NAME -o jsonpath='{.data.token}' | base64 --decode)
    CMDPRESS "kubectl get secret $SECRET_NAME -o jsonpath='{.data.token}' | base64 --decode"
    TOKEN=$(kubectl get secret $SECRET_NAME -o jsonpath='{.data.token}' | base64 --decode)
    echo $TOKEN

    echo; PRESS "-- Accessing API using a Bearer token (secret value in default service account of default namespace):"

    echo; PRESS "[Insecure https] API access:"
    RUN curl -s $API_URL/api/v1 --header \"Authorization: Bearer $TOKEN\" --insecure | TRUNCATE_LINES 10

    echo; PRESS "[Secure https (using cacert)] API access:"
    RUN curl -s $API_URL/api/v1 --header \"Authorization: Bearer $TOKEN\" --cacert cacert.pem | TRUNCATE_LINES 10

    echo; PRESS "[Secure https (using cacert)] API access: (access forbidden for default serviceaccount)"
    RUN curl -s $API_URL/api/v1/nodes --header \"Authorization: Bearer $TOKEN\" --cacert cacert.pem | TRUNCATE_LINES 10
}

KUBECTL_GET_VERBOSE
KUBECTL_RAW
CURL_CERTS
CURL_TOKEN
KUBECTL_PROXY
exit







exit


