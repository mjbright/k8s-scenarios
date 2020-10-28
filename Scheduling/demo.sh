#!/bin/bash

die() { echo "$0: die - $*" >&2; exit 1; }


RC=../demos.rc
[ ! -f $RC ] && die "Missing rc file '$RC'"
. $RC

CLEANUP() {
    RUN kubectl label node master team-
    RUN kubectl label node worker1 team-
    kubectl get deploy | grep web-node-aff && RUN kubectl delete deploy web-node-aff
}

CLEANUP

PRESS "Initial example, no labels on nodes: can't schedule Pods"
RUN kubectl create -f 1.nodeAffinity.team/deploy_web_nodeAffinity.yaml
RUN kubectl get pods -o wide

PRESS "Now add team=dev label on master node and see Pods get scheduled"
RUN kubectl label node master team=dev
#RUN kubectl delete -f 1.nodeAffinity.team/deploy_web_nodeAffinity.yaml 
#RUN kubectl get pods -o wide
#RUN kubectl create -f 1.nodeAffinity.team/deploy_web_nodeAffinity.yaml
RUN kubectl get pods -o wide

PRESS "Now add team=staging label on worker1 node, delete and recreate deployment, and see Pods get scheduled differently"
RUN kubectl label node worker1 team=staging
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

exit 0

