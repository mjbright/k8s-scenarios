#!/bin/bash

#!/bin/bash

RELEASE=1.25.4

die()   { echo "$0: die - $*" >&2; exit 1; }
PRESS() { echo $*; echo "Press <return>"; read DUMMY; }
RUN()   { CMD=$*; echo ; PRESS "-- $CMD"; $CMD; RET=$?; [ $RET -ne 0 ] && echo "Error: Command returned $RET"; }

HOST=$(hostname); case $HOSTNAME in
  *cp)    NODE_NAME=$( kubectl get nodes -o name | grep -m1 cp | sed 's?.*/??' );;
  *work*) die "Must be run from 'cp' Node";; # NODE_NAME=$( kubectl get nodes -o name | grep -m1 work | sed 's?.*/??' );;
  *)      die "Unrecognised node name"
esac; ssh worker uptime || die "ssh access to 'worker' must be enabled"

UPGRADE_NODE() { NODE_NAME="$1"; shift;  SSH="$1"; shift;
    PRESS "About to upgrade Node '$NODE_NAME' to release '$RELEASE'"

    RUN $SSH sudo apt update; RUN $SSH sudo apt-cache madison kubeadm
    RUN $SSH sudo apt-mark unhold kubeadm; RUN $SSH sudo apt-get install -y kubeadm=${RELEASE}-00; RUN $SSH sudo apt-mark hold kubeadm
    RUN $SSH sudo kubeadm version
    RUN kubectl drain $NODE_NAME --ignore-daemonsets
    RUN $SSH sudo kubeadm upgrade plan
    RUN $SSH kubeadm config images pull
    [ -z "$SSH" ] && RUN $SSH sudo kubeadm upgrade apply v${RELEASE}
    [ ! -z "$SSH" ] && RUN $SSH sudo kubeadm upgrade node
    RUN kubectl get node
    RUN $SSH sudo apt-mark unhold kubelet kubectl; RUN $SSH sudo apt-get install -y kubelet=${RELEASE}-00 kubectl=${RELEASE}-00; RUN $SSH sudo apt-mark hold kubelet kubectl
    RUN $SSH sudo systemctl daemon-reload; RUN $SSH sudo systemctl restart kubelet
    RUN kubectl get node
    RUN kubectl uncordon $NODE_NAME
    RUN kubectl get node
}

UPGRADE_NODE cp     ""
UPGRADE_NODE worker "ssh -t worker"

