#!/usr/bin/env bash

# Derived from:
# - https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/


export RELEASE=1.31.1
MINOR_RELEASE=${RELEASE%.*}
KUBE_PKG_V="${RELEASE}-1.1"

HOSTNAME=$(hostname)

#echo "RELEASE=$RELEASE MINOR_RELEASE=$MINOR_RELEASE KUBE_PKG_V=$KUBE_PKG_V"
#exit

PROMPTS=1
USECOLOR=1
USE_PV=1
#PV_PROMPT=0
PV_RATE=20

## -- Func: ------------------------------------------------------------------------------

die() { echo "$0: die - $*" >&2; exit 1; }

PV() {
    [ $USE_PV -eq 0 ] && {
        cat
        return
    }
    pv -qL $PV_RATE
    #[ $PV_PROMPT -eq 0 ] && return
    #read _DUMMY
}

READ_OPTIONS() {
    [ $PROMPTS -eq 0 ] && return 0

    while true; do
        echo -n "Press <return> "
        read DUMMY

        [ "${DUMMY#!!}" != "${DUMMY}" ] && {
            echo "-- $LASTCMD"
            eval $LASTCMD
            continue
        }

        if [ "${DUMMY#!}" != "${DUMMY}" ];then
            if [ "${DUMMY#!*}" != "${DUMMY#!}" ];then
                local CMD=${DUMMY#!}
                bash -x $CMD
            else
                PS1='debug \u@\h \w> ' bash
            fi
            continue
        fi

        [ "${DUMMY}" = "q" ] && exit 0
        [ "${DUMMY}" = "Q" ] && exit 0

        [ "${DUMMY}" = "s" ] && return 1
        [ "${DUMMY}" = "S" ] && return 1

        [ "${DUMMY#vf*}" != "${DUMMY}" ] && vi $CURRENT_FILE

        [ "${DUMMY#vp*}" != "${DUMMY}" ] && RUN kubectl get $CURRENT_POD
        [ "${DUMMY#dp*}" != "${DUMMY}" ] && RUN kubectl describe $CURRENT_POD

        [ "${DUMMY#vd*}" != "${DUMMY}" ] && RUN kubectl get $CURRENT_DEPLOY
        [ "${DUMMY#dd*}" != "${DUMMY}" ] && RUN kubectl describe $CURRENT_DEPLOY

        [ -z "${DUMMY}" ] && return 0
    done

    # # HELP:
    # # [ "${DUMMY#h*}" != "${DUMMY}" ] && Show opts, re-read DUMMY
    # return 0
}

# DEMO_HEADER: Show section (first arg in green), then prompt for input
DEMO_HEADER() { echo;echo; GREEN  "$1"; shift; echo "$*";  PRESS ""; }
STEP_HEADER() { echo;      GREEN  "$1"; shift; echo "$*";  }

#
# Function: PRESS <prompt>
# Prompt user to PRESS <return> to continue
# Exit if the user enters q or Q
#
PRESS() {
    echo -e $NORMAL
    echo; echo $*
    READ_OPTIONS
}

CPRESS() {
    #echo
    #echo "CPRESS $1"
    #echo "CPRESS ${1,,}"
    case ${1,,} in
        red)     shift; RED "$*";     echo;;
        green)   shift; GREEN "$*";   echo;;
        yellow)  shift; YELLOW "$*";  echo;;
        blue)    shift; BLUE "$*";    echo;;
        magenta) shift; MAGENTA "$*"; echo;;
        cyan)    shift; CYAN "$*";    echo;;
        *)       shift; echo "$*"; echo;;
    esac | PV
    echo -e $NORMAL
    READ_OPTIONS
}

## -- COLOUR FUNCTIONS -----------------------------------------------

SET_COLOURS() {
    ## -- COLOUR VARIABLES -----------------------------------------------

    #    NORMAL;                 BOLD;                   INVERSE;

    if [ $USECOLOR -ne 0 ]; then
        BLACK='\e[00;30m';    B_BLACK='\e[01;30m';    BG_BLACK='\e[07;30m'
        WHITE='\e[00;37m';    B_WHITE='\e[01;37m';    BG_WHITE='\e[07;37m'
        RED='\e[00;31m';      B_RED='\e[01;31m';      BG_RED='\e[07;31m'
        GREEN='\e[00;32m';    B_GREEN='\e[01;32m'     BG_GREEN='\e[07;32m'
        YELLOW='\e[00;33m';   B_YELLOW='\e[01;33m'    BG_YELLOW='\e[07;33m'
        BLUE='\e[00;34m'      B_BLUE='\e[01;34m'      BG_BLUE='\e[07;34m'
        MAGENTA='\e[00;35m'   B_MAGENTA='\e[01;35m'   BG_MAGENTA='\e[07;35m'
        CYAN='\e[00;36m'      B_CYAN='\e[01;36m'      BG_CYAN='\e[07;36m'
    else
        BLACK='';    B_BLACK='';    BG_BLACK=''
        WHITE='';    B_WHITE='';    BG_WHITE=''
        RED='';      B_RED='';      BG_RED=''
        GREEN='';    B_GREEN=''     BG_GREEN=''
        YELLOW='';   B_YELLOW=''    BG_YELLOW=''
        BLUE=''      B_BLUE=''      BG_BLUE=''
        MAGENTA=''   B_MAGENTA=''   BG_MAGENTA=''
        CYAN=''      B_CYAN=''      BG_CYAN=''
    fi
    NORMAL='\e[00m'
}

_colour=$NORMAL
I_colour=$NORMAL
#_LAST_colour=$NORMAL

BLACK()   { local l_f1_LAST_colour=$_colour; _colour=$BLACK;   echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f1_LAST_colour; echo -en $_colour; echo -n "$*";    }
WHITE()   { local l_f2_LAST_colour=$_colour; _colour=$WHITE;   echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f2_LAST_colour; echo -en $_colour; echo -n "$*";    }
RED()     { local l_f3_LAST_colour=$_colour; _colour=$RED;     echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f3_LAST_colour; echo -en $_colour; echo -n "$*";    }
GREEN()   { local l_f4_LAST_colour=$_colour; _colour=$GREEN;   echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f4_LAST_colour; echo -en $_colour; echo -n "$*";    }
YELLOW()  { local l_f5_LAST_colour=$_colour; _colour=$YELLOW;  echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f5_LAST_colour; echo -en $_colour; echo -n "$*";    }
BLUE()    { local l_f6_LAST_colour=$_colour; _colour=$BLUE;    echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f6_LAST_colour; echo -en $_colour; echo -n "$*";    }
MAGENTA() { local l_f7_LAST_colour=$_colour; _colour=$MAGENTA; echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f7_LAST_colour; echo -en $_colour; echo -n "$*";    }
CYAN()    { local l_f8_LAST_colour=$_colour; _colour=$CYAN;    echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f8_LAST_colour; echo -en $_colour; echo -n "$*";    }

B_BLACK()   { local l_f1_LAST_colour=$_colour; _colour=$B_BLACK;   echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f1_LAST_colour; echo -en $_colour; echo -n "$*";    }
B_WHITE()   { local l_f2_LAST_colour=$_colour; _colour=$B_WHITE;   echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f2_LAST_colour; echo -en $_colour; echo -n "$*";    }
B_RED()     { local l_f3_LAST_colour=$_colour; _colour=$B_RED;     echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f3_LAST_colour; echo -en $_colour; echo -n "$*";    }
B_GREEN()   { local l_f4_LAST_colour=$_colour; _colour=$B_GREEN;   echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f4_LAST_colour; echo -en $_colour; echo -n "$*";    }
B_YELLOW()  { local l_f5_LAST_colour=$_colour; _colour=$B_YELLOW;  echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f5_LAST_colour; echo -en $_colour; echo -n "$*";    }
B_BLUE()    { local l_f6_LAST_colour=$_colour; _colour=$B_BLUE;    echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f6_LAST_colour; echo -en $_colour; echo -n "$*";    }
B_MAGENTA() { local l_f7_LAST_colour=$_colour; _colour=$B_MAGENTA; echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f7_LAST_colour; echo -en $_colour; echo -n "$*";    }
B_CYAN()    { local l_f8_LAST_colour=$_colour; _colour=$B_CYAN;    echo -en $_colour; echo -n "$1"; shift ; _colour=$l_f8_LAST_colour; echo -en $_colour; echo -n "$*";    }


RUN() {
    #PROMPTS=1
    EVAL=0
    [ "$1" = "-eval" ] && { shift; EVAL=1;    }
    [ "$1" = "-np"   ] && { shift; PROMPTS=0; }

    echo;
    CPRESS yellow "-- $*"
    #YELLOW "-- $*"; echo
    #READ_OPTIONS
    #echo -en $NOMRAL

    local RET
    if [ $EVAL -eq 0 ]; then
        $*
        RET=$?
    else
        eval "$*"
        RET=$?
    fi

    LASTCMD=$*
    return $RET
}

CTR_CLEANUP() {
    sudo ctr -n k8s.io c rm $( sudo ctr -n k8s.io c ls | awk '!/^CONTAINER/ { print $1; }' )
    TASKS=$( sudo ctr -n k8s.io task ls | awk '!/^TASK / { print $1; }' ) 
    for TASK in $TASK; do
        CMD="sudo ctr -n k8s.io task kill -s SIGKILL -a $TASK"
        YELLOW "-- $CMD"
        $CMD
    done

    TASKS=$( sudo ctr -n k8s.io task ls | awk '!/^TASK / { print $1; }' ) 
    for TASK in $TASK; do
        CMD="sudo ctr -n k8s.io task rm $TASK"
        YELLOW "-- $CMD"
        $CMD
    done

    CONTAINERS=$( sudo ctr -n k8s.io c ls | awk '!/^CONTAINER / { print $1; }' ) 
    for C in $CONTAINERS; do
        CMD="sudo ctr -n k8s.io c rm $C"
        YELLOW "-- $CMD"
        $CMD
    done
}

CLEANUP_LOCAL() {
    if which helm; then
        ps aux | grep -v kubeadm_install | grep -v grep | grep kube &&
            for release in $( helm ls -A | grep -v ^NAME | awk ' { print "$2/$1"; }' ); do NS=${release%/*}; release=${release#*/};  RUN helm uninstall -n $NS $release; done
        for repo in $( helm repo ls | grep -v ^NAME | awk ' { print $1; }' ); do RUN helm repo remove $repo; done
    fi

    RM_KUBE=0
    dpkg -l | grep "^ii " | grep kubelet && RM_KUBE=1
    dpkg -l | grep "^hi " | grep kubelet && RM_KUBE=1
    [ $RM_KUBE -ne 0 ] && {
        RUN sudo systemctl disable --now kubelet
        RUN sudo kubeadm reset -f

        [ -d /etc/kubernetes ] && RUN sudo rm -rf /etc/kubernetes
        [ -d /var/lib/etcd   ] && RUN sudo rm -rf /var/lib/etcd

        RUN sudo apt-mark unhold kubelet kubeadm kubectl
        RUN sudo apt-get remove -y kubelet=$KUBE_PKG_V kubeadm=$KUBE_PKG_V kubectl=$KUBE_PKG_V
    }

    KUBE_PIDS=$( ps aux | grep kube | grep -v grep | grep -v kubeadm_install | awk '{ print $2; }' )
    [ ! -z "$KUBE_PIDS" ] && RUN sudo kill -9 $KUBE_PIDS

    if which ctr; then
        CTR_CLEANUP
    fi

    dpkg -l | grep "^ii " | grep containerd && {
        RUN sudo systemctl disable --now containerd
        RUN sudo apt-get remove -y containerd.io
        RUN sudo apt-get update
    }

    for FILE in /etc/containerd /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/kubernetes.list /etc/apt/keyrings/docker.asc /etc/apt/keyrings/kubernetes-apt-keyring.gpg; do
        [ -f $FILE ] && RUN sudo rm -f $FILE
    done
}

INSTALL_CONTAINERD() {
    # Based on instructions at: https://docs.docker.com/engine/install/ubuntu/
    RUN sudo apt-get update
    RUN sudo apt upgrade -y

    RUN sudo apt-get install -y ca-certificates curl
    # gnupg2 software-properties-common apt-transport-https socat
    RUN sudo install -m 0755 -d /etc/apt/keyrings
    RUN sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    RUN sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    arch=$(dpkg --print-architecture)
    os_info=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")

    CPRESS yellow "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $os_info stable | sudo tee /etc/apt/sources.list.d/docker.list"
    echo \
      "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $os_info stable" |
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    RUN sudo apt-get update

    #sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    RUN sudo apt-get install -y containerd.io

    # Configure containerd:
 
    RUN -eval "containerd config default | sudo tee /etc/containerd/config.toml"
    CPRESS yellow "sudo sed -i /etc/containerd/config.toml -e 's/SystemdCgroup *=.*/SystemdCgroup = true/g'"
    sudo sed -i /etc/containerd/config.toml -e 's/SystemdCgroup *=.*/SystemdCgroup = true/g'

    RUN sudo systemctl restart containerd
    RUN sudo systemctl enable containerd
    RUN sudo systemctl status containerd --no-pager
}

CONFIG_CONTAINERD() {
    # From: https://kubernetes.io/docs/setup/production-environment/container-runtimes/

    # sysctl params required by setup, params persist across reboots
    CPRESS yellow "echo net.ipv4.ip_forward = 1 | sudo tee /etc/sysctl.d/k8s.conf"
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

    # Apply sysctl params without reboot
    RUN sudo sysctl --system
}

INSTALL_KUBE() {
    RUN sudo apt-get update
    # apt-transport-https may be a dummy package; if so, you can skip that package
    RUN sudo apt-get install -y apt-transport-https ca-certificates curl gpg socat
    # Note: socat needed to avoid message: "[WARNING FileExisting-socat]: socat not found in system path"


    # Download the public signing key for the Kubernetes package repositories. The same signing key is used for all repositories so you can disregard the version in the URL:

    # If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
    RUN sudo mkdir -p -m 755 /etc/apt/keyrings
    CPRESS yellow "curl -fsSL https://pkgs.k8s.io/core:/stable:/v${MINOR_RELEASE}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v${MINOR_RELEASE}/deb/Release.key |
        sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    CPRESS yellow "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${MINOR_RELEASE}/deb/ / | sudo tee /etc/apt/sources.list.d/kubernetes.list"
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${MINOR_RELEASE}/deb/ /" |
        sudo tee /etc/apt/sources.list.d/kubernetes.list

    RUN sudo apt-get update
    RUN sudo apt-get install -y kubelet=$KUBE_PKG_V kubeadm=$KUBE_PKG_V kubectl=$KUBE_PKG_V
    RUN sudo apt-mark hold kubelet kubeadm kubectl
}

CONFIG_KUBE() {
    RUN sudo swapoff -a

    RUN sudo systemctl enable --now kubelet

    # As https://github.com/bottlerocket-os/bottlerocket/issues/3052:
    # br_netfilter required on cp node (for kubeadm init):
    RUN sudo modprobe br_netfilter

    CPRESS yellow "cat <<EOF (net.bridge rules) | sudo tee /etc/sysctl.d/k8s.conf"
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

    CPRESS yellow "cat <<EOF (overlay|br_netfilter) | sudo tee /etc/modules-load.d/containerd.conf"
    cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

    RUN sudo sysctl --system

    grep -q k8scp /etc/hosts || {
        CPRESS yellow "Adding k8scp entry into /etc/hosts"
        awk '/ cp$/ { print $1 " k8scp"; }' /etc/hosts | sudo tee -a /etc/hosts
        grep k8scp /etc/hosts
    }
}

INIT_KUBE() {
    # From https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/
    CPRESS yellow sudo kubeadm init --control-plane-endpoint "k8scp:6443" --pod-network-cidr "192.168.0.0/16"
    sudo kubeadm init --control-plane-endpoint "k8scp:6443" --pod-network-cidr "192.168.0.0/16" |&
        tee kubeadm-init.op

    RUN mkdir -p ~/.kube
    RUN sudo cp /etc/kubernetes/admin.conf ~/.kube/config
    RUN sudo chown -R student:student ~/.kube/

    RUN kubectl get no
}

INSTALL_HELM() {
    CPRESS yellow "curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash"
    curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
    return

    HELM_VERSION=3.18.2
    ARCH=amd64

    wget -P /tmp/ https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz
    tar tf /tmp/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz
    tar -C /tmp -xf /tmp/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz
    ls -al /tmp/linux-${ARCH}/helm
    sudo mv /tmp/linux-${ARCH}/helm  /usr/local/bin/
    which helm
    helm version
}

INSTALL_CILIUM() {
    RUN helm repo add cilium https://helm.cilium.io/
    CPRESS yellow "helm template cilium cilium/cilium --version 1.17.4 -n kube-system  > cilium.yaml"
    helm template cilium cilium/cilium --version 1.17.4 -n kube-system  > cilium.yaml

    RUN kubectl apply -f cilium.yaml
}

CLEANUP_REMOTE_WORKER() {
    scp $0 worker:/tmp/

    echo "---- worker: ----------------"
    ssh worker "set -x; chmod +x /tmp/kubeadm_install.sh; ls -al /tmp/kubeadm_install.sh; /tmp/kubeadm_install.sh -np -rm"
}

INSTALL_WORKER() {
    scp $0 worker:/tmp/

    echo
    grep -m1 -A3 "kubeadm join" ~/kubeadm-init.op > /tmp/join_cp.sh
    grep -A1 "kubeadm join" ~/kubeadm-init.op | tail -2 > /tmp/join_worker.sh

    scp /tmp/join_worker.sh worker:/tmp/
    # ssh worker "set -x; chmod +x /tmp/kubeadm_install.sh; ls -al /tmp/kubeadm_install.sh; /tmp/kubeadm_install.sh -x -np -A"
    ssh worker "set -x; chmod +x /tmp/kubeadm_install.sh; ls -al /tmp/kubeadm_install.sh; /tmp/kubeadm_install.sh -np -A"

    echo
    read -p "About to join worker to this node"
    ssh worker "set -x; chmod +x /tmp/join_worker.sh; sudo bash -x /tmp/join_worker.sh"

    echo
    RUN kubectl get no -w
}

INSTALL() {
    INSTALL_CONTAINERD
    CONFIG_CONTAINERD
    INSTALL_KUBE
    CONFIG_KUBE

    case $HOSTNAME in
        *cp)
            INIT_KUBE
            INSTALL_HELM
            INSTALL_CILIUM
            kubectl taint node --all node-role.kubernetes.io/control-plane-
            ;;
        *cp*)
            kubectl taint node --all node-role.kubernetes.io/control-plane-
            ;;
        *wo*)
            ;;
        *)
            die "Unrecognized node name '$HOSTNAME'"
    esac


    # node-role.kubernetes.io/control-plane:NoSchedule
}

DEPLOY_WEB() {
    # kubectl get po -w -o wide
    kubectl get deploy web | grep "^web " && {
        echo "Deleting old deployment 'web' ..."
        kubectl delete deploy web
        sleep 5
    }
    kubectl get svc web | grep "^web " && {
        echo "Deleting old service 'web' ..."
        kubectl delete svc web
    }
    RUN kubectl create deploy web --image mjbright/k8s-demo:1 --replicas 10
    RUN kubectl expose deploy web --port 80
    echo "Waiting for all pods to be ready ..."
    #sleep 5
    #RUN kubectl wait pod --all --for=condition=Ready -l app=web --namespace=default
    RUN kubectl wait pod --for=condition=Ready -l app=web

    RUN kubectl get pod -o wide
    RUN kubectl get svc

    SVC_IP=$( kubectl get svc web  | awk '/^web / { print $3; }' )
    #while true; do RUN curl ${SVC_IP}/1; sleep 0.5; done
    while true; do
        CMD="curl ${SVC_IP}/1"
        YELLOW "-- $CMD"; echo
        $CMD
        sleep 0.5
    done
}

## -- Args: ------------------------------------------------------------------------------

dpkg -l | grep -q "^ii .*pv" ||
    RUN sudo apt-get install -y pv

SET_COLOURS

[ -z "$1" ] && set -- -A

while [ ! -z "$1" ]; do
    case $1 in
          # For testing:
          -x) set -x;;
          +x) set +x;;
          -ex) exit 0;;

         -pv) USE_PV=1;;
         +pv) USE_PV=0;;
         -np) PROMPTS=0;;
         -bw) USECOLOR=0; SET_COLOURS;;

         -A)  INSTALL
              exit $?
              ;;

         -c1|-cd|-co*)
              INSTALL_CONTAINERD
              CONFIG_CONTAINERD
              exit $?
              ;;

        -k1|-ku*) INSTALL_KUBE
              CONFIG_KUBE
              exit $?
              ;;

        -k2|-ik*) INIT_KUBE
              exit $?
              ;;

        -k3|+ku*) INSTALL_HELM
              INSTALL_CILIUM
              RUN kubectl taint node --all node-role.kubernetes.io/control-plane-
              exit $?
              ;;

        -k4|-web) DEPLOY_WEB
              exit $?
              ;;

        -k5|-wo) INSTALL_WORKER
              exit $?
              ;;

        -ta*) RUN kubectl taint node --all node-role.kubernetes.io/control-plane-
              exit $?
              ;;

        -rel) export RELEASE=$1;;

         #-rm) CLEANUP_LOCAL; CLEANUP_REMOTE_WORKER; exit $?;;
         -rm) CLEANUP_LOCAL; exit $?;;
         -rm-cp|-cp-rm) CLEANUP_LOCAL        ; exit $?;;
         -rm-wo|-wo-rm) CLEANUP_REMOTE_WORKER; exit $?;;

        *) die "Unknown option '$1'";;
    esac
    shift
done

## -- Main: ------------------------------------------------------------------------------

# INSTALL

# read -p "About to INSTALL_CONTAINERD" ; INSTALL_CONTAINERD
# read -p "About to CONFIG_CONTAINERD" ; CONFIG_CONTAINERD
# read -p "About to INSTALL_KUBE"; INSTALL_KUBE
# read -p "About to CONFIG_KUBE"; CONFIG_KUBE
# read -p "About to INIT_KUBE"; INIT_KUBE

