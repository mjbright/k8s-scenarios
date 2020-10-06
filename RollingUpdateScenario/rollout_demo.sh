#!/bin/sh

NAME=ckad-demo
IMAGE_BASE=mjbright/ckad-demo
DEPLOY=deploy/$NAME
SVC=svc/$NAME

# NOTE: kubectl create deploy ckad-demo --image mjbright/ckad-demo:1 --dry-run=client -o yaml | kubectl create -f - --record=true
# Will only record:
#     REVISION  CHANGE-CAUSE
#     1         kubectl create --filename=- --record=true
# in rollout history


## Functions: ---------------------------------------------------------

press() {
    #BANNER "$*"
    [ $PROMPTS -eq 0 ] && return

    echo "Press <return>"
    read _DUMMY
    [ "$_DUMMY" = "q" ] && exit 0
    [ "$_DUMMY" = "Q" ] && exit 0
}

RUN() {
    CMD=$@
    echo; echo "-- CMD: $CMD"
    eval $CMD
}

PAUSE_RUN() {
    CMD=$@
    echo; echo "-- CMD: $CMD"
    read _DUMMY
    [ "$_DUMMY" = "q" ] && exit 0
    [ "$_DUMMY" = "Q" ] && exit 0

    eval $CMD
}

CLEANUP() {
   kubectl delete $DEPLOY
   kubectl delete $SVC
}

BLUE_GREEN() {
   # CLEANUP:
   kubectl get svc ckad-demo 2>/dev/null | grep -q ckad-demo &&
       RUN kubectl delete svc ckad-demo
   kubectl get deploy ckad-demo-blue 2>/dev/null | grep -q ckad-demo-blue &&
       RUN kubectl delete deploy ckad-demo-blue
   kubectl get deploy ckad-demo-green 2>/dev/null | grep -q ckad-demo-green &&
       RUN kubectl delete deploy ckad-demo-green

   PAUSE_RUN kubectl create deploy ckad-demo-blue --image mjbright/ckad-demo:1
   PAUSE_RUN kubectl create deploy ckad-demo-green --image mjbright/ckad-demo:3

   # Replace 1st ocurrence of -blue (part of Service label, not the selector):
   kubectl expose deploy ckad-demo-blue --port 80 --type ClusterIP --name ckad-demo --dry-run=client -o yaml |
       sed '1,/-blue/s/-blue//' > service-ckad-demo.yaml

   PAUSE_RUN cat service-ckad-demo.yaml

   PAUSE_RUN kubectl create -f service-ckad-demo.yaml 
   SVC_IP=$(kubectl get svc ckad-demo -o custom-columns=CIP:.spec.clusterIP --no-headers)
   PAUSE_RUN kubectl describe svc ckad-demo
   PAUSE_RUN curl -sL $SVC_IP

   # Replace selector:
   sed 's/-blue/-green/' < service-ckad-demo.yaml > service-green.yaml 
   #cp -a service-blue.yaml service-green.yaml 

   PAUSE_RUN cat service-green.yaml 
   PAUSE_RUN kubectl apply -f service-green.yaml 

   PAUSE_RUN kubectl describe svc ckad-demo
   PAUSE_RUN curl -sL $SVC_IP
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
    ROLLING) PAUSE_RUN kubectl create deploy $NAME --image ${IMAGE_BASE}:1;;
    RECREATE)
        # RECREATE:
        kubectl create deploy ckad-demo --image mjbright/ckad-demo:1 --dry-run=client -o yaml > deploy_ckad.yaml
        sed -e 's/strategy: {}/strategy:\n    type: Recreate/' < deploy_ckad.yaml > deploy_ckad_recreate.yaml
        PAUSE_RUN kubectl create -f deploy_ckad_recreate.yaml
        #exit 0
	;;
    BLUEGREEN)
       	BLUE_GREEN; exit $?;;
esac

PAUSE_RUN kubectl expose $DEPLOY  --port 80
kubectl get all | grep $NAME

PAUSE_RUN kubectl scale $DEPLOY --replicas=10
PAUSE_RUN kubectl set image $DEPLOY ${NAME}=${IMAGE_BASE}:2 --record
RUN kubectl rollout status ${DEPLOY}
PAUSE_RUN kubectl rollout history ${DEPLOY}

PAUSE_RUN kubectl set image ${DEPLOY} ${NAME}=${IMAGE_BASE}:3 --record
RUN kubectl rollout status ${DEPLOY}
PAUSE_RUN kubectl rollout history ${DEPLOY}
PAUSE_RUN kubectl rollout undo ${DEPLOY}

exit 0


