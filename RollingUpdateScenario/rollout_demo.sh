#!/bin/bash

. ../demos.rc

#APP_NAME=ckad-demo
APP_NAME=web
APP_CONTAINER=ckad-demo
IMAGE_BASE=mjbright/ckad-demo
DEPLOY=deploy/$APP_NAME
SVC=svc/$APP_NAME

TMP=~/tmp/demos
mkdir -p $TMP

# NOTE: kubectl create deploy $APP_NAME --image ${IMAGE_BASE}:1 --dry-run=client -o yaml | kubectl create -f - --record=true
# Will only record:
#     REVISION  CHANGE-CAUSE
#     1         kubectl create --filename=- --record=true
# in rollout history


## Functions: ---------------------------------------------------------

PRESS() {
    #BANNER "$*"
    [ $PROMPTS -eq 0 ] && return

    echo "Press <return>"
    read _DUMMY
    [ "$_DUMMY" = "q" ] && exit 0
    [ "$_DUMMY" = "Q" ] && exit 0
}

#RUN() {
#    CMD=$@
#    echo; echo "-- CMD: $CMD"
#    eval $CMD
#}
#
#PAUSE_RUN() {
#    CMD=$@
#    echo; echo "-- CMD: $CMD"
#    read _DUMMY
#    [ "$_DUMMY" = "q" ] && exit 0
#    [ "$_DUMMY" = "Q" ] && exit 0
#
#    eval $CMD
#}

CLEANUP() {
   kubectl delete $DEPLOY
   kubectl delete $SVC
}

BLUE_GREEN() {
   # CLEANUP:
   kubectl get svc $APP_NAME 2>/dev/null | grep -q $APP_NAME &&
       RUN kubectl delete svc $APP_NAME
   kubectl get deploy ${APP_NAME}-blue 2>/dev/null | grep -q ${APP_NAME}-blue &&
       RUN kubectl delete deploy ${APP_NAME}-blue
   kubectl get deploy ${APP_NAME}-green 2>/dev/null | grep -q ${APP_NAME}-green &&
       RUN kubectl delete deploy ${APP_NAME}-green

   RUN_PRESS kubectl create deploy ${APP_NAME}-blue --image ${IMAGE_BASE}:1
   RUN_PRESS kubectl create deploy ${APP_NAME}-green --image ${IMAGE_BASE}:3

   # Replace 1st ocurrence of -blue (part of Service label, not the selector):
   kubectl expose deploy ${APP_NAME}-blue --port 80 --type ClusterIP --name ${APP_NAME} --dry-run=client -o yaml |
       sed '1,/-blue/s/-blue//' > $TMP/service-${APP_NAME}.yaml

   RUN_PRESS cat $TMP/service-${APP_NAME}.yaml

   RUN_PRESS kubectl create -f $TMP/service-${APP_NAME}.yaml 
   SVC_IP=$(kubectl get svc ${APP_NAME} -o custom-columns=CIP:.spec.clusterIP --no-headers)
   RUN_PRESS kubectl describe svc ${APP_NAME}
   RUN_PRESS curl -sL $SVC_IP

   # Replace selector:
   sed 's/-blue/-green/' < $TMP/service-${APP_NAME}.yaml > $TMP/service-green.yaml 
   #cp -a service-blue.yaml service-green.yaml 

   RUN_PRESS cat $TMP/service-green.yaml 
   RUN_PRESS kubectl apply -f $TMP/service-green.yaml 

   RUN_PRESS kubectl describe svc ${APP_NAME}
   RUN_PRESS curl -sL $SVC_IP
}

## Args: --------------------------------------------------------------

STRATEGY=ROLLING

while [ ! -z "$1" ]; do
    case $1 in
        -rol*) STRATEGY=ROLLING;;
        -rec*) STRATEGY=RECREATE;;
        -bg*)  STRATEGY=BLUEGREEN;;
        *) die "Unknown option '$1'";;
    esac
    shift
done

## Main: --------------------------------------------------------------

CLEANUP 2>/dev/null

case $STRATEGY in
    ROLLING) RUN_PRESS kubectl create deploy $APP_NAME --image ${IMAGE_BASE}:1;;
    RECREATE)
        # RECREATE:
        YAML1=$TMP/deploy_${APP_NAME}.yaml
        YAML2=$TMP/deploy_${APP_NAME}_recreate.yaml
	echo
	echo "Creating yaml file for blue and green deployments:"
        kubectl create deploy ${APP_NAME} --image ${IMAGE_BASE}:1 --dry-run=client -o yaml > $YAML1
        ls -al $YAML1
        sed -e 's/strategy: {}/strategy:\n    type: Recreate/' < $YAML1 > $YAML2
        ls -al $YAML2
        diff $YAML1 $YAML2
    	RUN_PRESS kubectl create -f $YAML2
        # exit $?
	;;
    BLUEGREEN)
       	BLUE_GREEN;
	PRESS "Cleanup"
	kubectl delete svc ${APP_NAME}
	kubectl delete deploy ${APP_NAME}-blue
	kubectl delete deploy ${APP_NAME}-green
	exit $?;;
esac

RUN_PRESS kubectl expose $DEPLOY  --port 80
kubectl get all | grep $APP_NAME

RUN_PRESS kubectl scale $DEPLOY --replicas=10

echo
echo "NOTE: remember pause/resume during rollout"
RUN_PRESS kubectl set image $DEPLOY ${APP_CONTAINER}=${IMAGE_BASE}:2 --record
RUN_PRESS kubectl rollout pause  $DEPLOY
RUN_PRESS kubectl rollout resume $DEPLOY
RUN kubectl rollout status ${DEPLOY}
RUN_PRESS kubectl rollout history ${DEPLOY}

RUN_PRESS kubectl set image ${DEPLOY} ${APP_CONTAINER}=${IMAGE_BASE}:3 --record
RUN kubectl rollout status ${DEPLOY}
RUN_PRESS kubectl rollout history ${DEPLOY}
RUN_PRESS kubectl rollout undo ${DEPLOY}

exit 0


