#!/bin/bash

cd $(dirname $0)
. ../demos.rc

FLAGS_ENV_FILE=/var/lib/kubelet/kubeadm-flags.env
FEATURE_FLAG="--feature-gates=EphemeralContainers=true"

# For info about configuring feature-gate:
#    https://www.shogan.co.uk/kubernetes/enabling-and-using-ephemeral-containers-on-kubernetes-1-16/

DEPLOY=ckad-demo
DEPLOY_IMAGE="mjbright/ckad-demo:1"

#ALL_NODES="master"
#ALL_NODES=$( echo $( kubectl get nodes --no-headers -o custom-columns=.NAME:.metadata.name ) )
MASTER_NODES=$( echo $( kubectl get nodes --no-headers -o custom-columns=.NAME:.metadata.name -l 'node-role.kubernetes.io/control-plane' ) )
WORKER_NODES=$( echo $( kubectl get nodes --no-headers -o custom-columns=.NAME:.metadata.name -l '!node-role.kubernetes.io/control-plane' ) )
ALL_NODES="$MASTER_NODES $WORKER_NODES"
OTHER_NODES=${ALL_NODES#master }

echo "MASTER_NODES='$MASTER_NODES'"
echo "WORKER_NODES='$WORKER_NODES'"
echo "ALL_NODES='$ALL_NODES'"
echo "OTHER_NODES='$OTHER_NODES'"

#OTHER_NODES="worker1"
CHECK_OTHER_NODES=1

## - Functions: -------------------------------------------------------

die() { echo -e "$0: die - $*" >&2; exit 1; }

CHECK_NODE() {
    ROLE=$1; shift
    NODE=$1; shift

    #ssh -qt $NODE sudo grep -q -- --feature-gates=EphemeralContainers=true $FLAGS_ENV_FILE && return 0
    ssh -qt $NODE sudo grep ^KUBELET_KUBEADM_ARGS $FLAGS_ENV_FILE
    ssh -qt $NODE sudo grep -q -- --feature-gates=EphemeralContainers=true $FLAGS_ENV_FILE && return 0
    local ERROR="$NODE: Feature flags not enabled on kubelet in $FLAGS_ENV_FILE\n"
    echo "    $ERROR"
    #ERRORS+=$ERROR
    return 1
}

CHECK_NODE_PROCS() {
    ROLE=$1; shift
    NODE=$1; shift

    if [ "$ROLE" = "control" ]; then
        #KUBE_PROCESSES="kube-apiserver kube-controller-manager kube-scheduler kubelet"
        KUBE_PROCESSES="kube-apiserver kube-controller-manager kube-scheduler /usr/bin/kubelet"
    else
        KUBE_PROCESSES="/usr/bin/kubelet"
    fi

    #ps -fade | grep kube-apiserver | grep -q -- --feature-gates=EphemeralContainers=true          || die "Feature flags not set on kube-apiserver"
    #ps -fade | grep kube-controller-manager | grep -q -- --feature-gates=EphemeralContainers=true || die "Feature flags not set on kube-controller-manager"
    #ps -fade | grep kube-scheduler | grep -q -- --feature-gates=EphemeralContainers=true          || die "Feature flags not set on kube-scheduler"
    #ps -fade | grep kubelet | grep -q -- --feature-gates=EphemeralContainers=true                 || die "Feature flags not set on kubelet"

    for KUBE_PROCESS in $KUBE_PROCESSES; do
        #echo "KP: $KUBE_PROCESS"
        ssh $NODE ps -fade |
	    grep " $KUBE_PROCESS " | grep -v grep | awk '{ print "    ", $2, $7, $8, $NF; }'
        ssh $NODE ps -fade | grep $KUBE_PROCESS | grep -q -- --feature-gates=EphemeralContainers=true || {
            local FATAL_ERROR="$NODE: Feature flags not set on running $KUBE_PROCESS process"
            echo "    $FATAL_ERROR"
            FATAL_ERRORS+=$FATAL_ERROR"\n"
            return 1
        }
    done
    return 0
}

CHECK_AND_MODIFY_NODE() {
    ROLE=$1; shift
    NODE=$1; shift

    #CHECK_NODE $NODE && return 0
    echo "CHECK_AND_MODIFY_NODE: $NODE"

    # Modify KUBELET config:
    RESTART=0
    CMD_CP_BAK="[ ! -f ${FLAGS_ENV_FILE}.bak ] && cp -a ${FLAGS_ENV_FILE} ${FLAGS_ENV_FILE}.bak"
    #echo "-- ssh $NODE sudo \"bash -c '$CMD_CP_BAK'\""
    ssh $NODE sudo "bash -c '$CMD_CP_BAK'"

    OLD_LINE=$(ssh $NODE sudo grep -m 1 ^KUBELET_KUBEADM_ARGS= ${FLAGS_ENV_FILE})
    if echo $OLD_LINE | grep -q -- $FEATURE_FLAG ; then
        echo "    Feature flag [$FEATURE_FLAG] is already set in $FLAGS_ENV_FILE"
    else
        NEW_LINE=$(echo $OLD_LINE | sed 's/KUBELET_KUBEADM_ARGS=[",'\'']\(.*\)[",'\'']$/KUBELET_KUBEADM_ARGS="\1/')
        NEW_LINE="$NEW_LINE $FEATURE_FLAG\""
        #echo OLD_LINE=$OLD_LINE
        #echo NEW_LINE=$NEW_LINE
        echo $NEW_LINE | ssh $NODE sudo "tee ${FLAGS_ENV_FILE}" >/dev/null
        RESTART=1
    fi
    
    echo; echo "- Checking processes on ${NODE} ..."
    CHECK_NODE_PROCS $ROLE $NODE || RESTART=1

    # Modify manifests: (assuming the same list on all nodes):
    if [ "$ROLE" = "control" ]; then
        for MANIFEST in $(ls -1 /etc/kubernetes/manifests/*.yaml); do
            manifest=${MANIFEST##*/}
            if [ "$manifest" != "etcd.yaml" ]; then
                if ssh $NODE sudo grep -q -- $FEATURE_FLAG $MANIFEST ; then
                    echo "    Feature flag [$FEATURE_FLAG] is already set in $manifest"
                else
	            ssh $NODE sudo sed -i.bak -e '/image:/i\\\ \ \ \ -\ '$FEATURE_FLAG $MANIFEST
                    RESTART=1
                fi
            fi
        done
    fi

    CHECK_NODE $ROLE $NODE || FATAL_ERRORS+="Failed to set config on '$NODE'"

    [ $RESTART -ne 0 ] && RESTART_KUBELET_N_ALL $NODE
}

RESTART_KUBELET_N_ALL() {
    NODE=$1; shift

    echo "- Restarting kubelet(++) processes on ${NODE} ..."
    echo "  $NODE: kubelet stop"
    ssh $NODE sudo service kubelet stop
    echo "  $NODE: daemon-reload"
    ssh $NODE sudo systemctl daemon-reload

    # REMOTE_PIDS=$(ssh $NODE ps -fade | awk '/ (kube-apiserver|kube-controller|kube-scheduler)/ { print $2; }')
    # REMOTE_PIDS=$(echo $REMOTE_PIDS) # Remove new-lines
    # MATCH_REMOTE_PIDS=$(echo $REMOTE_PIDS | sed 's/ /|/g')
    # echo "  $NODE: kill kube-* procs [$REMOTE_PIDS]"
    # ssh $NODE sudo "kill -9 $REMOTE_PIDS"

    # sleep 5
    # ssh $NODE sudo "ps -fade" | grep -E "$MATCH_REMOTE_PIDS"

    # kubectl -n kube-system get pods kube-apiserver-master kube-controller-manager-master kube-scheduler-master
    #kubectl -n kube-system delete pods kube-apiserver-master kube-controller-manager-master kube-scheduler-master
    kubectl -n kube-system delete pods kube-controller-manager-master kube-scheduler-master
    kubectl -n kube-system delete pods kube-apiserver-master

    #ssh $NODE sudo service kubelet restart
    echo "  $NODE: kubelet start"
    ssh $NODE sudo service kubelet start
}

STEP0_CONFIG_CHECK() {
    # See: https://www.europeclouds.com/blog/debugging-with-ephemeral-containers-in-k8s
    #     - "Enabling ephemeral containers"
    #
    # "You need to set to true the feature gates flag of the Kubernetes control plane elements:
    # - API Server, Controller Manager, Scheduler and Kubelet.
    #
    # If your cluster was created using kubeadm, you can find the manifests for the three main
    # elements in /etc/kubernetes/manifests in the master nodes.
    # Add the following line into the container command arguments.
    #     - --feature-gates=EphemeralContainers=true
    #
    # For the kubelet, check EnvironmentFile entry in /etc/systemd/system/kubelet.service.d/10-kubeadm.conf.
    # e.g. /var/lib/kubelet/kubeadm-flags.env
    #
    # On worker & master nodes add '--feature-gates=EphemeralContainers=true' into the KUBELET_KUBEADM_ARGS variable definition,
    #  e.g. to have:
    #  In master: /var/lib/kubelet/kubeadm-flags.env:
    #    KUBELET_KUBEADM_ARGS="--network-plugin=cni --pod-infra-container-image=k8s.gcr.io/pause:3.2 --feature-gates=EphemeralContainers=true"
    #  In worker1: /var/lib/kubelet/kubeadm-flags.env:
    #    KUBELET_KUBEADM_ARGS="--network-plugin=cni --pod-infra-container-image=k8s.gcr.io/pause:3.2 --feature-gates=EphemeralContainers=true"
    #
    # Then reload/restart the kubelet:
    #    sudo systemctl daemon-reload
    #    sudo service kubelet restart
    # and check the feature-gates flag is present on all 4 processes:
    # 

    # ps -fade | grep kube-apiserver | grep -q -- --feature-gates=EphemeralContainers=true ||
    #     echo "Feature flags not set on kube-apiserver"
    # ps -fade | grep kube-controller-manager | grep -q -- --feature-gates=EphemeralContainers=true ||
    #     echo "Feature flags not set on kube-controller-manager"
    # ps -fade | grep kube-scheduler | grep -q -- --feature-gates=EphemeralContainers=true ||
    #     echo "Feature flags not set on kube-scheduler"
    # sudo service kubelet restart
    # ps -fade | grep kubelet | grep -q -- --feature-gates=EphemeralContainers=true ||
    #     echo "Feature flags not set on kubelet"

    SECTION1 "Checking EphemeralContainers feature-gates flags on all nodes"

    ERRORS=""
    FATAL_ERRORS=""

    if [ $CHECK_OTHER_NODES -ne 0 ]; then
        ROLE="control"
        for NODE in $MASTER_NODES; do 
            echo; echo "- Checking configuration on ${NODE} ..."
            CHECK_AND_MODIFY_NODE $ROLE $NODE
        done
        ROLE="worker"
        for NODE in $WORKER_NODES; do 
            echo; echo "- Checking configuration on ${NODE} ..."
            CHECK_AND_MODIFY_NODE $ROLE $NODE
        done
    fi

    #[ ! -z "$ERRORS" ] && {}

    [ ! -z "$FATAL_ERRORS" ] && {
        echo
        #STEP0_SETUP_CONFIG_HELP
        #echo
        die "Errors seen in configuration checks:\n$(echo $FATAL_ERRORS | sed 's/^/    /')"
    }
}

## - Args: ------------------------------------------------------------

## - Main: ------------------------------------------------------------

# 1. Service with problem - would be great an interesting use case
#    - could be several problems and step through them all
#    - what order, fix pods then service or vice-versa?
# 2. Identify problem - extract Pod from service to investigate
#    - change Pod label, observe new Pod created
#    - try exec to Pod - no shell !!
# 3. Now add Ephemeral container

ERRORS=""
#[ $CHECK_OTHER_NODES -ne 0 ] && for OTHER_NODE in $OTHER_NODES; do \
[ $CHECK_OTHER_NODES -ne 0 ] && for OTHER_NODE in $ALL_NODES; do \
    echo "Checking ssh connectivity 'master->$OTHER_NODE'"; ssh $OTHER_NODE uptime || ERRORS+="Cannot connect to $OTHER_NODE from master\n"; done ; \
        [ ! -z "$ERRORS" ] && die "ssh connectivity errors:\n$ERRORS"

STEP0_CONFIG_CHECK

