#!/bin/bash

cd $(dirname $0)

press() {
    echo "$*"
    echo "Press <return>"
    read DUMMY
    [ "$DUMMY" = "q" ] && exit 0
    [ "$DUMMY" = "Q" ] && exit 0
}

RUN() {
    echo; press "-- $*"
    $*
}

echo "In other window: run command" 
press "watch kubectl get pv,pvc,pods"

RUN kubectl delete -f ./

FILES="./pv_hostpath.yaml ./pv2_hostpath.yaml ./pv3_hostpath.yaml ./pvc.yaml ./pod_hostpath_pvc.yaml "
for FILE in $FILES; do
    RUN vim $FILE
    RUN kubectl create -f $FILE
done

echo; kubectl get pods -o custom-columns=NODE:.spec.nodeName
NODE=$( kubectl get pods -o custom-columns=NODE:.spec.nodeName --no-headers )

[ -z "$NODE" ] && NODE="worker2"
read -p "Enter node name [$NODE]: " NODE_CHOICE
[ ! -z "$NODE_CHOICE" ] && NODE="$NODE_CHOICE"

RUN ssh $NODE ls -al /tmp/data01/
RUN ssh $NODE tail -100f /tmp/data01/date.log

RUN kubectl delete -f ./

