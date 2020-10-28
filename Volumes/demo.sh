#!/bin/bash

DIR=$(dirname $0)

cd $DIR

. ../demos.rc

#press() {
#    echo "$*"
#    echo "Press <return>"
#    read DUMMY
#    [ "$DUMMY" = "q" ] && exit 0
#    [ "$DUMMY" = "Q" ] && exit 0
#}
#
#RUN() {
#    echo; press "-- $*"
#    $*
#}

HL1 "In other window: run command" 
PRESS "watch kubectl get pv,pvc,pods"

RUN_EMPTYDIR_DEMO() {
    TODO
    cd emptyDir
    cd $DIR
}

RUN_HOSTPATH_DEMO() {
    TODO
    cd hostPath
    cd $DIR
}

RUN_HOSTPATH_PC_PVC_DEMO() {
    cd hostPath_PV_PVC

    RUN kubectl delete -f ./

    SECTION1 "Creating Persistent Volumes for initial demo"
    FILES="./pv_hostpath.yaml ./pv2_hostpath.yaml ./pv3_hostpath.yaml ./pvc.yaml ./pod_hostpath_pvc.yaml"
    for FILE in $FILES; do
        RUN cat $FILE
        RUN kubectl create -f $FILE
    done

    echo; kubectl get pods -o wide
    NODE=$( kubectl get pods -o custom-columns=NODE:.spec.nodeName --no-headers )

    [ -z "$NODE" ] && NODE="worker2"
    read -p "Enter node name [$NODE]: " NODE_CHOICE
    [ ! -z "$NODE_CHOICE" ] && NODE="$NODE_CHOICE"

    #VOL=/tmp/data01
    VOL=/tmp/data03
    RUN ssh $NODE ls -al ${VOL}/
    RUN ssh $NODE tail -100f ${VOL}/date.log

    SECTION1 "Creating extra Persistent Volumes with StorageClass"
    FILES="./pv4_sc_hostpath.yaml ./pv5_sc_hostpath.yaml ./pvc2_sc.yaml ./pod2_hostpath_pvc2.yaml"
    for FILE in $FILES; do
        RUN cat $FILE
        RUN kubectl create -f $FILE
    done

    RUN kubectl delete -f ./

    cd $DIR
}

RUN_HOSTPATH_PC_PVC_DEMO

