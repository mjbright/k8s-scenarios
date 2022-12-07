#!/bin/bash

#
# Simple script to speed up upgrading of a Kubernetes cluster
#
# - assumes 2nd Node is 'worker' (set NODE2 variable below)
# - assumes password-less ssh to 2nd Node is configured
#

NODE2=worker
HOSTNAME=$(hostname)

RELEASE=1.25.4

## Funcs: ----------------------------------------------------------

die()   { echo "$0: die - $*" >&2; exit 1; }

PRESS() {
    echo $*
    echo "Press <return>"
    read DUMMY
}

RUN()   {
    CMD=$*

    echo ; PRESS "-- $CMD"
    $CMD
    RET=$?

    [ $RET -ne 0 ] && echo "Error: Command returned $RET"
}

UPGRADE_NODE() {
    NODE_NAME="$1"; shift;
    SSH="$1"; shift;

    PRESS "About to upgrade Node '$NODE_NAME' to release '$RELEASE'"

    RUN $SSH sudo apt update
    RUN $SSH sudo apt-cache madison kubeadm
    RUN $SSH sudo apt-mark unhold kubeadm
    RUN $SSH sudo apt-get install -y kubeadm=${RELEASE}-00
    RUN $SSH sudo apt-mark hold kubeadm
    RUN $SSH sudo kubeadm version
    RUN kubectl drain $NODE_NAME --ignore-daemonsets
    RUN $SSH sudo kubeadm upgrade plan
    RUN $SSH kubeadm config images pull
    [ -z "$SSH" ] && RUN $SSH sudo kubeadm upgrade apply v${RELEASE}
    [ ! -z "$SSH" ] && RUN $SSH sudo kubeadm upgrade node
    RUN kubectl get node
    RUN $SSH sudo apt-mark unhold kubelet kubectl
    RUN $SSH sudo apt-get install -y kubelet=${RELEASE}-00 kubectl=${RELEASE}-00
    RUN $SSH sudo apt-mark hold kubelet kubectl
    RUN $SSH sudo systemctl daemon-reload
    RUN $SSH sudo systemctl restart kubelet
    RUN kubectl get node
    RUN kubectl uncordon $NODE_NAME
    RUN kubectl get node
}

DEFAULT_ACTION_2_NODE_UPGRADE() {
    # Upgrade this (cp?) Node:
    UPGRADE_NODE $NODE_NAME     ""

    # Upgrade second (worker?) Node: connect via ssh
    UPGRADE_NODE $NODE2         "ssh -t $NODE2"
}

## Args: ----------------------------------------------------------

# Determine on what node we are running - a cp or worker node ?

case $HOSTNAME in
  *cp)    NODE_NAME=$( kubectl get nodes -o name | grep -m1 cp | sed 's?.*/??' );;
  *work*) die "Must be run from 'cp' Node";; # NODE_NAME=$( kubectl get nodes -o name | grep -m1 work | sed 's?.*/??' );;
  *)      die "Unrecognised node name '$HOSTNAME'"
esac

while [ ! -z "$1" ]; do
    case $1 in
        -n) shift; NODE=$1; 
            ssh $NODE uptime ||
                die "ssh access to '$NODE' must be enabled"

            UPGRADE_NODE $NODE2         "ssh -t $NODE2"
            exit $?
            ;;

         *) die "Unknown option '$1'";;
    esac
done

## Main: ----------------------------------------------------------

ssh $NODE2 uptime ||
    die "ssh access to '$NODE2' must be enabled"

DEFAULT_ACTION_2_NODE_UPGRADE

