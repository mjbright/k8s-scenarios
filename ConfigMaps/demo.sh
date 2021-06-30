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
   kubectl delete deploy    deploy-test-cm
   kubectl delete configmap test-cm

   while ! kubectl get pod -l app=deploy-test-cm 2>&1 | grep -q "No resources"; do
       echo "CLEANUP: Waiting for deploy-test-cm Pods to terminate ..."
       sleep 5
   done
}

## Args: --------------------------------------------------------------

CLEANUP

RUN_PRESS kubectl create -f test-cm.yaml
RUN_PRESS kubectl get configmap test-cm
RUN_PRESS kubectl get configmap test-cm -o yaml

RUN_PRESS kubectl create -f deploy-test-cm.yaml
sleep 1
POD=$( kubectl get pods -l app=deploy-test-cm -o name )
if [ "${POD## *}" != "$POD" ]; then
    die "Found multiple pods '$POD'"
fi

RUN_PRESS kubectl exec -it $POD -- df -h  /home/vol-cm
RUN_PRESS kubectl exec -it $POD -- ls -al /home/vol-cm
RUN_PRESS kubectl exec -it $POD -- cat /home/vol-cm/file1

RUN_PRESS kubectl apply -f test-cm2.yaml
START=$( date +%s )
RUN_PRESS kubectl get configmap test-cm -o yaml
RUN_PRESS kubectl exec -it $POD -- ls -al /home/vol-cm

let LOOP=0
while ! kubectl exec -it $POD -- ls -al /home/vol-cm/file4 >/dev/null 2>&1; do
    let LOOP=LOOP+1
    echo "[$LOOP] Waiting for ConfigMap changes to be seen by deploy-test-cm Pod [file4 to appear] ...."
    sleep 5
done
END=$( date +%s )
let TOOK=END-START
echo "file4 seen after $TOOK seconds"

RUN_PRESS kubectl exec -it $POD -- cat /home/vol-cm/file4
echo

exit 1

