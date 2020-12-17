#!/bin/bash

die() { echo "$0: die - $*" >&2; exit 1; }


RC=../demos.rc
[ ! -f $RC ] && die "Missing rc file '$RC'"
. $RC

MASTER_LABEL_KEY="node-role.kubernetes.io/master"

GET_NODES() {
    MASTERS=$(kubectl get nodes -l $MASTER_LABEL_KEY -o custom-columns=NAME:.metadata.name --no-headers)
    NUM_MASTERS=$(echo "$MASTERS" | wc -l)
    WORKERS=$(kubectl get nodes -l "!$MASTER_LABEL_KEY" -o custom-columns=NAME:.metadata.name --no-headers)
    NUM_WORKERS=$(echo "$WORKERS" | wc -l)

    echo "Cluster has $NUM_MASTERS controllers <"$MASTERS">"
    echo "Cluster has $NUM_WORKERS workers     <"$WORKERS">"

    #MASTER1="${MASTERS%% *}"
    #WORKER1="${WORKERS%% *}"
    MASTER1=$(echo "$MASTERS" | head -1)
    WORKER1=$(echo "$WORKERS" | head -1)
    WORKER2=$(echo "$WORKERS" | head -2 | tail -1)
    WORKER3=$(echo "$WORKERS" | head -3 | tail -1)
}

CLEANUP() {
    RUN kubectl label node --all team-
    kubectl get deploy | grep web-node-aff && RUN kubectl delete deploy web-node-aff
    kubectl get deploy | grep web          && RUN kubectl delete deploy web         
}

NODENAME_EXAMPLE() {
    SECTION1 "nodeName example"
    PRESS "About to create Pod using nodeName"

    sed -e "s/nodeName: master/nodeName: $MASTER1/" deploy_web_nodeName.yaml > /tmp/deploy_web_nodeName.yaml 
    #RUN grep -C 100 nodeName: /tmp/deploy_web_nodeName.yaml
    HL "-- cat /tmp/deploy_web_nodeName.yaml"; echo; PRESS
    grep --color=always -C 100 nodeName: /tmp/deploy_web_nodeName.yaml

    RUN kubectl create -f /tmp/deploy_web_nodeName.yaml
    RUN kubectl get pods -o wide

    PRESS "About to delete Pods"
    RUN kubectl delete -f /tmp/deploy_web_nodeName.yaml
}

NODESELECTOR_EXAMPLE() {
    SECTION1 "nodeSelector example"
    PRESS "About to create Pod using nodeSelector"

    RUN kubectl label node $WORKER1 zone=workergroup1 --overwrite
    [ ! -z "$WORKER2" ] && RUN kubectl label node $WORKER2 zone=workergroup1 --overwrite

    #set -x
    #sed -e "s?/hostname: worker1?/hostname: $WORKER1?" deploy_web_nodeSelector.yaml > /tmp/deploy_web_nodeSelector.yaml 
    #set +x
    #HL "-- cat /tmp/deploy_web_nodeSelector.yaml"; echo; PRESS
    #grep --color=always -C 100 hostname: /tmp/deploy_web_nodeSelector.yaml

    #RUN kubectl create -f /tmp/deploy_web_nodeSelector.yaml

    HL "-- cat deploy_web_nodeSelector.yaml"; echo; PRESS
    grep --color=always -C 100 zone: deploy_web_nodeSelector.yaml
    RUN kubectl create -f deploy_web_nodeSelector.yaml
    RUN kubectl get pods -o wide

    PRESS "About to delete Pod"
    RUN kubectl delete -f deploy_web_nodeSelector.yaml
}

NODEAFFINITY_EXAMPLE() {
    SECTION1 "nodeAffinity example"

    PRESS "Initial example, no 'team' labels on nodes: can't schedule Pods"
    RUN kubectl create -f 1.nodeAffinity.team/deploy_web_nodeAffinity.yaml
    RUN kubectl get pods -o wide

    DEV_NODE=$MASTER1
    [ ! -z "$WORKER2" ] &&
    PRESS "Now add team=dev label on $DEV_NODE node and see Pods get scheduled (ONLY after re-creation)"
    RUN kubectl label node $DEV_NODE team=dev --overwrite
    RUN kubectl delete -f 1.nodeAffinity.team/deploy_web_nodeAffinity.yaml 
    RUN kubectl get pods -o wide
    RUN kubectl create -f 1.nodeAffinity.team/deploy_web_nodeAffinity.yaml
    RUN kubectl get pods -o wide

    APPLY=$WORKER1
    [ ! -z "$WORKER3" ] && APPLY+=" $WORKER3"
    PRESS "Now add team=staging label on '$APPLY' node(s), delete and recreate deployment, and see Pods get scheduled differently"
    for NODE in $APPLY; do
        RUN kubectl label node $NODE team=staging --overwrite
    done

    RUN kubectl delete -f 1.nodeAffinity.team/deploy_web_nodeAffinity.yaml 
    RUN kubectl get pods -o wide
    PRESS ""
    RUN kubectl get pods -o wide
    PRESS ""

    #RUN kubectl create -f 1.nodeAffinity.team/deploy_web_nodeAffinity.yaml
    #RUN kubectl get pods -o wide

    RUN kubectl get pods -o wide
    RUN kubectl create -f 1.nodeAffinity.team/deploy_web_nodeAffinity_preferTeam.yaml 
    RUN kubectl get pods -o wide
}

GET_NODES
CLEANUP

#NODENAME_EXAMPLE
#NODESELECTOR_EXAMPLE
NODEAFFINITY_EXAMPLE
exit 0

