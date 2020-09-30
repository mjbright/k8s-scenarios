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

read -p "Enter node name [worker2]: " NODE
[ -z "$NODE" ] && NODE="worker2"

RUN ssh $NODE ls -al /tmp/data01/
RUN ssh $NODE tail -100f /tmp/data01/date.log

RUN kubectl delete -f ./

