#!/bin/bash

cd $(dirname $0)

# DONE:
# - DONE: Implement skip option on press (need callers to skip action if return code of 1)
# - DONE: shell breakout
#
# TODO:
# - Optional steps (yesno)
#   - scale up/down deployments
#   - use nodeName for Pod placement
#   - use labels for deployment placement (nodeSelector)
#   - use labels for daemonset placement
# - Batch Jobs
#   - Use of successJobHistory / failedJobHistory / what about maximum time?
#   - Show 'Job' Completed state => '7/7'

press() {
    echo "$*"

    local DUMMY
    while true; do
        echo "Press <return>"
        read DUMMY
        [ -z "$DUMMY" ] && return 0

        [ "$DUMMY" = "q" ] && exit 0
        [ "$DUMMY" = "Q" ] && exit 0
    
        [ "$DUMMY" = "c" ] && clear
        [ "$DUMMY" = "C" ] && clear

        [ "$DUMMY" = "!" ] && /bin/bash --rcfile nestedbash.rc
	[ "${DUMMY#\!}" != "$DUMMY" ] && ${DUMMY#\!}

        [ "$DUMMY" = "s" ] && return 1
        [ "$DUMMY" = "S" ] && return 1
    done
}

function yesno
{
    resp=""
    default=""
    [ ! -z "$2" ] && default="$2"

    while [ 1 ]; do
        if [ ! -z "$default" ];then
            echo -n "$1 [yYnNqQ] [$default]:"
            read resp
            [ -z "$resp" ] && resp="$default"
        else
            echo -n "$1 [yYnNqQ]:"
            read resp
        fi
        [ \( "$resp" = "q" \) -o \( "$resp" = "Q" \) ] && exit 0
        [ \( "$resp" = "y" \) -o \( "$resp" = "Y" \) ] && return 0
        [ \( "$resp" = "n" \) -o \( "$resp" = "N" \) ] && return 1
    done
}

RUN() {
    echo; press "-- $*" && $*
}

DIFF_YAML() {
    YAML1=$1; shift
    YAML2=$1; shift

    echo ; echo "Showing diffs between (<)$YAML1 and (>)$YAML2:"
    RUN diff -w $YAML1 $YAML2
}

CAT_CREATE_DELETE_YAML() {
    local DIFF_YAML=""
    if [ "$1" = "--diff" ]; then
        shift; DIFF_YAML=$1; shift;
    fi

    KIND=$1; shift
    YAMLS=$*

    echo; echo "======== ${KIND} ==========";
    for YAML in $YAMLS; do
        RUN cat $YAML

        [ ! -z "$DIFF_YAML" ] && DIFF_YAML $DIFF_YAML $YAML
        RUN kubectl create -f $YAML
        RUN kubectl delete -f $YAML
    done
}

CLEANUP() {
    echo
    echo "Cleaning up (may produce many errors)"
    RUN kubectl delete -f ./
}

## main: -------------------------------------------------------

echo "In other window: run one of the following monitors:" 
echo "- k1spy all"
echo "- watch kubectl get dep,ds,rs,pod,sts,job,cj"
press ""

CLEANUP

CAT_CREATE_DELETE_YAML "Deployment" deploy_ckad.yaml
# yesno "Scale up deployment?" && kubectl scale deploy ckad-demo --replicas=20

# CAT_CREATE_DELETE_YAML "ReplicaSet (alone)" rset_ckad.yaml

#DIFF_YAMLS deploy_ckad.yaml dset_ckad.yaml
CAT_CREATE_DELETE_YAML --diff deploy_ckad.yaml "DaemonSet" dset_ckad.yaml

echo; echo "-- StatefulSet"
RUN cat sset_ckad.yaml
DIFF_YAML deploy_ckad.yaml sset_ckad.yaml
#CAT_CREATE_DELETE_YAML "StatefulSet (show scale down/delete)" sset_ckad.yaml
RUN kubectl apply -f sset_ckad.yaml

yesno "Test deletion of 0-th Pod from StatefulSet?" && {
    RUN kubectl delete pod ckad-demo-sset-0
}

yesno "Demonstrate use of headless ClusterIP service?" && {
    RUN cat svc_sset_ckad.yaml
    RUN kubectl apply -f svc_sset_ckad.yaml

    RUN cat hdless_svc_sset_ckad.yaml
    DIFF_YAML hdless_svc_sset_ckad.yaml svc_sset_ckad.yaml

    RUN kubectl apply -f hdless_svc_sset_ckad.yaml

    echo ; echo "Cleaning up services ..."
    RUN kubectl delete -f svc_sset_ckad.yaml
    RUN kubectl delete -f hdless_svc_sset_ckad.yaml
}

yesno "Demonstrate upgrade of StatefulSet?" && {
    RUN kubectl apply -f sset_ckad_v2.yaml
    DIFF_YAML sset_ckad.yaml sset_ckad_v2.yaml
}

RUN kubectl scale sts ckad-demo-sset --replicas=0
RUN kubectl delete sts ckad-demo-sset

CAT_CREATE_DELETE_YAML "Job"      job_ckad.yaml
CAT_CREATE_DELETE_YAML "Cron job" cronjob_ckad.yaml

CLEANUP

