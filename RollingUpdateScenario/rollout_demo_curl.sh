#!/bin/sh

#NAME=ckad-demo
NAME=web
[ ! -z "$1" ] && NAME=$1

GET_SVC_IP() {
    IP=$(kubectl get svc $NAME --no-headers | awk '{ print $3; }')
}

GET_SVC_IP

CURL_OPTS="--connect-timeout 2 --max-time 4"
WGET_OPTS="--timeout 4 --tries 1"

LOOP_CONNECT_FROM_LOCAL_NODE() {
    while true; do
        if [ -z "$IP" ]; then
            GET_SVC_IP
        else
            curl $CURL_OPTS ${IP}:80/1;
            [ $? -ne 0 ] && GET_SVC_IP
        fi
        sleep 1;
    done
}

FROM_POD() {
    set -x
    kubectl run testpod --rm -it --image alpine -- sh -c "while true; do wget $WGET_OPTS -qO - web/1; sleep 1; done"
}

FROM_POD

