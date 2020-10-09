#!/bin/sh

NAME=ckad-demo
[ ! -z "$1" ] && NAME=$1

GET_SVC_IP() {
    IP=$(kubectl get svc $NAME --no-headers | awk '{ print $3; }')
}

GET_SVC_IP

CURL_OPTS="--connect-timeout 2 --max-time 4"

while true; do
    if [ -z "$IP" ]; then
        GET_SVC_IP
    else
        curl $CURL_OPTS ${IP}:80/c;
        [ $? -ne 0 ] && GET_SVC_IP
    fi
    sleep 1;
done

