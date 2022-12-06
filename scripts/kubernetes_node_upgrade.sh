#!/bin/bash

RELEASE=1.25.4

die() { echo "$0: die - $*" >&2; exit 1; }
PRESS() { echo $*; echo "Press <return>"; read DUMMY; }
RUN()   { CMD=$*; echo ; PRESS "-- $CMD"; $CMD; RET=$?; [ $RET -ne 0 ] && echo "Error: Command returned $RET"; }

case $(hostname) in
    *cp)   NODE_NAME=$( kubectl get nodes -o name | grep -m1 cp | sed 's?.*/??' );;
    *work) NODE_NAME=$( kubectl get nodes -o name | grep -m1 work | sed 's?.*/??' );;
    *)     die "Unrecognised node name"
esac

PRESS "About to upgrade Node '$NODE_NAME' to release '$RELEASE'"

RUN sudo apt update
RUN sudo apt-cache madison kubeadm
RUN sudo apt-mark unhold kubeadm
RUN sudo apt-get install -y kubeadm=${RELEASE}-00
RUN sudo apt-mark hold kubeadm
RUN sudo kubeadm version
RUN kubectl drain $NODE_NAME --ignore-daemonsets
RUN sudo kubeadm upgrade plan
RUN kubeadm config images pull
RUN sudo kubeadm upgrade apply v${RELEASE}
RUN kubectl get node
RUN sudo apt-mark unhold kubelet kubectl
RUN sudo apt-get install -y kubelet=${RELEASE}-00 kubectl=${RELEASE}-00
RUN sudo apt-mark hold kubelet kubectl
RUN sudo systemctl daemon-reload
RUN sudo systemctl restart kubelet
RUN kubectl get node
RUN kubectl uncordon $NODE_NAME
RUN kubectl get node
