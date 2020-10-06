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

## Args: --------------------------------------------------------------

STRATEGY=ROLLING

while [ ! -z "$1" ]; do
    case $1 in
        -rol*) STRATEGY=ROLLING;;
        -rec*) STRATEGY=RECREATE;;
        *) die "Unknown option '$1'";;
    esac
    shift
done

## Main: --------------------------------------------------------------

CLEANUP 2>/dev/null

if [ "$STRATEGY" = "ROLLING" ]; then
    PAUSE_RUN kubectl create deploy $NAME --image ${IMAGE_BASE}:1
else
    # RECREATE:
    kubectl create deploy ckad-demo --image mjbright/ckad-demo:1 --dry-run=client -o yaml > deploy_ckad.yaml
    sed -e 's/strategy: {}/strategy:\n    type: Recreate/' < deploy_ckad.yaml > deploy_ckad_recreate.yaml
    PAUSE_RUN kubectl create -f deploy_ckad_recreate.yaml
    #exit 0
fi
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

