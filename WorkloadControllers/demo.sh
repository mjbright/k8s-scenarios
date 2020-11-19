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
press "watch kubectl get dep,ds,rs,pod,sts,job,cj"

SHOW_TYPE() {
    KIND=$1; shift
    YAMLS=$*

    echo; echo "-- ${KIND}:";
    for YAML in $YAMLS; do
        RUN cat $YAML
        RUN kubectl create -f $YAML
        RUN kubectl delete -f $YAML
    done
}

RUN kubectl delete -f ./

SHOW_TYPE "Deployment" deploy_ckad.yaml
# SHOW_TYPE "ReplicaSet (alone)" rset_ckad.yaml

SHOW_TYPE "DaemonSet" dset_ckad.yaml

echo; echo "-- StatedulSet"
#SHOW_TYPE "StatefulSet (show scale down/delete)" sset_ckad.yaml
RUN kubectl apply -f sset_ckad.yaml

RUN cat svc_sset_ckad.yaml
RUN kubectl apply -f svc_sset_ckad.yaml

RUN cat hdless_svc_sset_ckad.yaml
RUN diff hdless_svc_sset_ckad.yaml svc_sset_ckad.yaml

RUN kubectl apply -f hdless_svc_sset_ckad.yaml

RUN kubectl apply -f sset_ckad_v2.yaml
RUN kubectl scale sts ckad-demo-sset --replicas=0
RUN kubectl delete sts ckad-demo-sset

# TODO: Use of successJobHistory / failedJobHistory / what about maximum time?
# TODO: Show Completed state
SHOW_TYPE "Job"      job_ckad.yaml
SHOW_TYPE "Cron job" cronjob_ckad.yaml

RUN kubectl delete -f ./

