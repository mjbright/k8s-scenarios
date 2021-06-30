#!/bin/bash

. ../demos.rc

TMP=~/tmp/demos
mkdir -p $TMP

## Functions: ---------------------------------------------------------

PRESS() {
    #BANNER "$*"
    [ $PROMPTS -eq 0 ] && return

    echo "Press <return>"
    read _DUMMY
    [ "$_DUMMY" = "q" ] && exit 0
    [ "$_DUMMY" = "Q" ] && exit 0
}

CLEANUP() {
   kubectl delete -f pod-containers.yaml 

   while ! kubectl get pod -l run=test-multi-containers 2>&1 | grep -q "No resources"; do
       echo "CLEANUP: Waiting for 'test-multi-containers' Pods to terminate ..."
       sleep 5
   done
}

## Args: --------------------------------------------------------------

CLEANUP

RUN_PRESS  cat pod-containers.yaml 
RUN_PRESS  kubectl create -f pod-containers.yaml 

while ! kubectl get pod test-multi-containers | grep Running; do
    kubectl get pod test-multi-containers
    echo "Waiting for container to start ..."; sleep 2;
done

RUN_PRESS kubectl logs test-multi-containers  -c init1
RUN_PRESS kubectl logs test-multi-containers  -c init2
RUN_PRESS kubectl logs test-multi-containers  -c nginx 
RUN_PRESS kubectl logs test-multi-containers  -c content

RUN_PRESS  kubectl describe pod test-multi-containers 

RUN_PRESS kubectl exec -it test-multi-containers curl 127.0.0.1
RUN_PRESS kubectl exec -it test-multi-containers curl 127.0.0.1
RUN_PRESS kubectl exec -it test-multi-containers curl 127.0.0.1

