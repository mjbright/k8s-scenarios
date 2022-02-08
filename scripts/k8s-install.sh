#!/bin/bash

# Quick launch options:
# -CP: hard-reset cluster (deletes cluster, removes packages)
#      followed by install_packages and kubeadm init
# -WO: hard-reset cluster (deletes cluster, removes packages)
#      followed by install_packages
#
# Quick control node: no prompts
#   $0 -R -ANP # hard-reset cluster (deletes cluster, removes packages)
#   $0 -r -ANP # soft-reset cluster (deletes cluster)
#   $0 -I -ANP # -I: install_packages and kubeadm init

# Quick worker node: no prompts (still need join afterwards):
#   $0 -R -ANP # hard-reset cluster (deletes cluster, removes packages
#   $0 -r -ANP # soft-reset cluster (deletes cluster)
#   $0 -i -ANP # -i: install_packages

# This script downloadable from:
#     https://github.com/mjbright/k8s-scenarios/blob/master/scripts/k8s-install.sh
# using:
#     wget https://raw.githubusercontent.com/mjbright/k8s-scenarios/master/scripts/k8s-install.sh

mkdir -p ~/tmp

POD_CIDR="192.168.0.0/16"

die() {
    echo -e "${RED}$0: die - ${NORMAL}$*" >&2
    for i in 0 1 2 3 4 5 6 7 8 9 10;do
        CALLER_INFO=`caller $i`
        [ -z "$CALLER_INFO" ] && break
        echo "    Line: $CALLER_INFO" >&2
    done
    exit 1
}

CLEANUP_DOCKER_CRIO() {
    RUN sudo apt-get remove -y docker.io containerd cri-tools
    RUN sudo apt autoremove -y

    # check for running processes
    #   dpkg -l | grep -iE "docker|container|cri"
    #   ls -al /var/run/ | grep -iE "docker|cri|container"
    #   ps -fade | grep -iE "docker|cri|container"
    #   ls -al /var/lib/ | grep -iE "docker|cri|container"

    sudo rm -rf /var/lib/containerd/ /var/lib/docker/
    sudo rm -rf /var/run/docker* /var/run/containerd/
}


# Installation loosely based on:
# - https://computingforgeeks.com/deploy-kubernetes-cluster-on-ubuntu-with-kubeadm

# TODO: remove DOCKER packages in hard-reset (which version docker.io docker-ce both?)
# TODO: Make configurable to use Docker/Containerd/Cri-o (+podman/buildah/skopeo)
#CONTAINER_ENGINE="DOCKER"
CONTAINER_ENGINE="CRIO"
INSTALL_CE=INSTALL_${CONTAINER_ENGINE}

PROMPTS=${PROMPTS:=1}
ALL_PROMPTS=${ALL_PROMPTS:=1}
ABS_NO_PROMPTS=0
FORCE_NODENAME=""

USECOLOR=${USECOLOR:=1}
VERBOSE_PROMPT=0
VERBOSE_PROMPT=1 # On first PRESS
VERBOSE_PROMPT=2 # Always
VERBOSE_PROMPT=1

HOSTNAME=$(hostname)
NODE="control"
NODE_ROLE="control"
NODE_NUM=""
INSTALL_MODE="GENERAL"

# START: SET_INSTALL DEFAULTS: ----------------------------------

## . /etc/os-release
# Fix the versions to use

export OS=xUbuntu_18.04 # Override true OS version
LFS_K8S_VERSION="1.21.1-00"
LFD_K8S_VERSION="1.22.1-00"

#K8S_VERSION="1.22.0-00"
K8S_VERSION="1.23.3-00"

LFS_K8S_REL=${LFS_K8S_VERSION%-00}
LFD_K8S_REL=${LFD_K8S_VERSION%-00}
K8S_REL=${K8S_VERSION%-00}
#K8S_MIN_VERSION=${K8S_REL%.*}

SET_INSTALL_MODE() {
    INSTALL_MODE=$1; shift

    case $INSTALL_MODE in
    *LFS458*|*lfs458*)
      K8S_VERSION=$LFS_K8S_VERSION; K8S_REL=$LFS_K8S_REL;
      K8S_MIN_VERSION=${K8S_REL%.*} # e.g. 1.21.1 => 1.21
      [ $NODE = "control" ] && NODE="k8scp"
      INSTALL_MODE="LFS458"
      ;;
    *LFD459*|*lfd459*)
      K8S_VERSION=$LFD_K8S_VERSION; K8S_REL=$LFD_K8S_REL;
      K8S_MIN_VERSION=${K8S_REL%.*}
      [ $NODE = "control" ] && NODE="k8scp"
      INSTALL_MODE="LFD459"
      ;;
    *)
      K8S_MIN_VERSION=${K8S_REL%.*}
      ;;
    esac
    echo "INSTALL_MODE=$INSTALL_MODE NODE=$NODE[$NODE_ROLE]"
    echo "K8S_REL=$K8S_REL K8S_VERSION[apt]=$K8S_VERSION"
      #die "K8S_MIN_VERSION='$K8S_MIN_VERSION'"

    [ -z "$K8S_MIN_VERSION" ] && die "[MODE=$INSTALL_MODE] K8S_MIN_VERSION is unset"
}

NODE_ROLE="control"
case $0 in
    *-w*) NODE="worker"; NODE_ROLE="worker" ;;
esac

SET_INSTALL_MODE $INSTALL_MODE

#[ -f /tmp/k8s-release ] && K8S_REL=$(cat /tmp/k8s-release)
RC=${0%.sh}.rc
[ -f $RC ] && {
    echo "Sourcing $RC ..."
    source $RC
}
# END:   SET_INSTALL DEFAULTS: ----------------------------------

USE_PV=1
PV_PROMPT=0
#PV_RATE=1000
#PV_RATE=100
#PV_RATE=10
PV_RATE=20

# TODO:
# Save all o/p
# - save specifically kubeadm join
# - say how to regenerate join command
#
# Demo
# - pretty usable o/p
# - Option to use pv for demo steps
# - input options
#
# Study https://devopscube.com/setup-kubernetes-cluster-kubeadm/
# - add all master steps 
# - add all worker steps
# - add api-sans-cert 127.0.0.1 (approx)
#
# Comment all steps (plus possible extra detail)
#
# More options
# - set PS1 (node role/namespace)
# - install metrics-server

## Functions: -------------------------------------------------

GET_NODE_INFO() {
    . /etc/lsb-release
    echo "OS: $DISTRIB_DESCRIPTION"
    #DISTRIB_ID=Ubuntu
    #DISTRIB_RELEASE=18.04
    #DISTRIB_CODENAME=bionic
    #DISTRIB_DESCRIPTION="Ubuntu 18.04.4 LTS"
    #echo "Kernel: $(uname -a)"
    echo "Kernel: $(uname -srv)"
    echo

    echo "CPUs: $( grep -c "model name" /proc/cpuinfo )"
    grep "model name" /proc/cpuinfo | sed 's/^/    /'
    echo "Memory:" $(awk '/MemTotal:.*kB/ { GB=int($2/1000000); printf "%s GBy\n", GB; }' /proc/meminfo)
}

READ_OPTIONS() {
    [ $PROMPTS -eq 0 ] && return 0
    #set -x

    local DUMMY
    while true; do
        if [ $VERBOSE_PROMPT -eq 0 ]; then
            echo -en "${NORMAL}Press <return> "
        else
            echo -en "${NORMAL}Press <return> [or ! q s] "
            [ $VERBOSE_PROMPT -eq 1 ] && VERBOSE_PROMPT=0
        fi
        read DUMMY

        [ "$DUMMY" = "!!" ] && {
            echo "-- $LASTCMD"
            eval $LASTCMD
            continue
        }

        if [ "${DUMMY#!}" != "${DUMMY}" ];then
            if [ "$DUMMY" = "!" ];then
                bash --rcfile <(echo "PS1='\\u@\\h \\w subshell> '") -i
                #PS1='debug \u@\h \w> ' bash
            else
                local CMD=${DUMMY#!}
                #echo "bash -x $CMD"
                #bash -x $CMD
                eval $CMD
                #bash --rcfile <(echo "PS1='subshell prompt: '") -i
            fi
            continue
        fi 

        [ "${DUMMY}" = "q" ] && exit 0
        [ "${DUMMY}" = "Q" ] && exit 0

        [ "${DUMMY}" = "s" ] && return 1
        [ "${DUMMY}" = "S" ] && return 1

        [ "${DUMMY#vf*}" != "${DUMMY}" ] && vi $CURRENT_FILE

        # [ "${DUMMY#vp*}" != "${DUMMY}" ] && RUN kubectl get $CURRENT_POD
        # [ "${DUMMY#dp*}" != "${DUMMY}" ] && RUN kubectl describe $CURRENT_POD

        # [ "${DUMMY#vd*}" != "${DUMMY}" ] && RUN kubectl get $CURRENT_DEPLOY
        # [ "${DUMMY#dd*}" != "${DUMMY}" ] && RUN kubectl describe $CURRENT_DEPLOY

        [ -z "${DUMMY}" ] && return 0
    done

    # # HELP:
    # # [ "${DUMMY#h*}" != "${DUMMY}" ] && Show opts, re-read DUMMY
    # return 0
}

SECTION1() {
    PROMPTS=1
    [ "$1" = "-np" ] && { shift; PROMPTS=0; }
    echo; echo "======== $*"
    READ_OPTIONS
}

SECTION2() {
    PROMPTS=1
    [ "$1" = "-np" ] && { shift; PROMPTS=0; }
    echo; echo "---- $*"
    READ_OPTIONS
}

PV() {
    [ $USE_PV -eq 0 ] && {
        cat
        return
    }
    pv -qL $PV_RATE
    [ $PV_PROMPT -eq 0 ] && return
    read _DUMMY
}

QRUN() {
    RUN -np $*
}

RUN() {
    #PROMPTS=1
    PROMPTS=$ALL_PROMPTS
    [ "$1" = "-np" ] && { shift; PROMPTS=0; }

    echo;
    YELLOW "-- $*" | PV; echo
    READ_OPTIONS
    [ $? -ne 0 ] && return

    eval "$*"
    local RET=$?
    [ $RET -ne 0 ] && echo -e "... returned ${RED}non-zero${NORMAL} exit code $RET"
    LASTCMD=$*
    return $RET
}

RUN_PRESS() {
    CPRESS "YELLOW" "-- $*";
    eval "$*";
}


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

## -- COLOUR FUNCTIONS -----------------------------------------------

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

I_BLACK()   { local l_f1_LAST_colour=$I_colour; I_colour=$BLACK;   echo -en $I_colour; echo -n "$1"; shift ; I_colour=$l_f1_LAST_colour; echo -en $_colour; echo -n "$*";    }
I_WHITE()   { local l_f2_LAST_colour=$I_colour; I_colour=$WHITE;   echo -en $I_colour; echo -n "$1"; shift ; I_colour=$l_f2_LAST_colour; echo -en $_colour; echo -n "$*";    }
I_RED()     { local l_f3_LAST_colour=$I_colour; I_colour=$RED;     echo -en $I_colour; echo -n "$1"; shift ; I_colour=$l_f3_LAST_colour; echo -en $_colour; echo -n "$*";    }
I_GREEN()   { local l_f4_LAST_colour=$I_colour; I_colour=$GREEN;   echo -en $I_colour; echo -n "$1"; shift ; I_colour=$l_f4_LAST_colour; echo -en $_colour; echo -n "$*";    }
I_YELLOW()  { local l_f5_LAST_colour=$I_colour; I_colour=$YELLOW;  echo -en $I_colour; echo -n "$1"; shift ; I_colour=$l_f5_LAST_colour; echo -en $_colour; echo -n "$*";    }
I_BLUE()    { local l_f6_LAST_colour=$I_colour; I_colour=$BLUE;    echo -en $I_colour; echo -n "$1"; shift ; I_colour=$l_f6_LAST_colour; echo -en $_colour; echo -n "$*";    }
I_MAGENTA() { local l_f7_LAST_colour=$I_colour; I_colour=$MAGENTA; echo -en $I_colour; echo -n "$1"; shift ; I_colour=$l_f7_LAST_colour; echo -en $_colour; echo -n "$*";    }
I_CYAN()    { local l_f8_LAST_colour=$I_colour; I_colour=$CYAN;    echo -en $I_colour; echo -n "$1"; shift ; I_colour=$l_f8_LAST_colour; echo -en $_colour; echo -n "$*";    }

NORMAL()  { echo -en $NORMAL; }

## -- HELPER FUNCTIONS -----------------------------------------------

# Highlight text
HL_OLD()  { YELLOW "$*"; }
HL()  {
  case "$1" in
    -green)   shift; GREEN   "$*";;
    -red)     shift; RED     "$*";;
    -blue)    shift; BLUE    "$*";;
    -cyan)    shift; CYAN    "$*";;
    -magenta) shift; MAGENTA "$*";;
    -yellow)  shift; YELLOW  "$*";;
    *)        YELLOW  "$*";;
  esac
}

# Highlight text ("1st argument" only)
HL1() {
  case $1 in
    -green|-red|-blue|-cyan|-magenta|-yellow) HL $1 "$2"; shift;;
    *)                                        YELLOW "$1";;
  esac
  shift;
  echo -n "$*";
}

#HL1 "A TEST \$USECOLOR=$USECOLOR"

# DEMO_HEADER: Show section (first arg in green), then prompt for input
DEMO_HEADER() { echo;echo; GREEN  "$HOSTNAME: $1 "; shift; echo "$*";  QPRESS ""; }
STEP_HEADER() { echo;      GREEN  "$HOSTNAME: $1 "; shift; echo "$*";  }

#
# Function: PRESS <prompt>
# Prompt user to PRESS <return> to continue
# Exit if the user enters q or Q
#
PRESS() {
    echo
    [ ! -z "$1" ] && echo $*
    [ $ALL_PROMPTS -eq 0 ] && return
    READ_OPTIONS
}

# ALWAYS PROMPT (ignore ALL_PROMPTS):
ALWAYS_WARN_PROMPT() {
    echo "Warning: $*"
    echo -n "Press <return> ['q' to quit]"
    read DUMMY
    [ "$DUMMY" = "q" ] && exit 0
    [ "$DUMMY" = "Q" ] && exit 0
}

QPRESS() {
    [ $ALL_PROMPTS -eq 0 ] && return
    echo -n "Press <return> "
    read DUMMY
}

CPRESS() {
    echo
    case $1 in
        RED)     shift; RED "$*";     echo;;
        GREEN)   shift; GREEN "$*";   echo;;
        YELLOW)  shift; YELLOW "$*";  echo;;
        BLUE)    shift; BLUE "$*";    echo;;
        MAGENTA) shift; MAGENTA "$*"; echo;;
        CYAN)    shift; CYAN "$*";    echo;;
        *)       shift; echo "$*"; echo;;
    esac
    READ_OPTIONS
}

#
# function YESNO <question> [<default>]
# e.g. use as:
#     YESNO "Edit reminder file?" && vi $reminder_file_tomerge
#
YESNO() {
    resp=""
    default=""
    PROMPT="$1"
    [ ! -z "$2" ] && default="$2"

    #echo "ALL_PROMPTS='$ALL_PROMPTS'"
    #echo "default='$default'"
    [ $ALL_PROMPTS -eq 0 ] && [ ! -z "$default" ] && {
        resp=$default
        [ \( "$resp" = "y" \) -o \( "$resp" = "Y" \) ] && return 0
        [ \( "$resp" = "n" \) -o \( "$resp" = "N" \) ] && return 1
    }

    while [ 1 ]; do
        if [ ! -z "$default" ];then
            YELLOW "$PROMPT" " [yYnNqQ] [$default]:"
            read resp
            [ -z "$resp" ] && resp="$default"
        else
            YELLOW "$PROMPT" " [yYnNqQ]:"
            read resp
        fi
        [ \( "$resp" = "q" \) -o \( "$resp" = "Q" \) ] && exit 0
        [ \( "$resp" = "y" \) -o \( "$resp" = "Y" \) ] && return 0
        [ \( "$resp" = "n" \) -o \( "$resp" = "N" \) ] && return 1
    done
}

COLOUR_ALL_STDIN() {
    echo -en $1; cat; echo -en $NORMAL
    echo
}

COLOUR_ALL_TEXT() {
    echo -en $1; cat; echo -en $NORMAL
    echo
}

COLOUR_STDIN() {
    #echo -e $(echo "%GREEN%test%RED%TEST%NORMAL%test%YELLOW%YELLOW\r\nSOME MORE TEXT" | sed -e "s/%GREEN%/\\${GREEN}/g" -e "s/%RED%/\\${RED}/g" -e "s/%NORMAL%/\\${NORMAL}/g" -e "s/%YELLOW%/\\\e[1;33m/g" -e "s/$/\\${NORMAL}/g") 

        #-e "s/ *%_/%/g" \
        #-e "s/_% /%/g" \

    sed \
        -e "s/ %BLACK% /\\${BLACK}/g" \
        -e "s/ %WHITE% /\\${WHITE}/g" \
        -e "s/ %RED% /\\${RED}/g" \
        -e "s/ %GREEN% /\\${GREEN}/g" \
        -e "s/ %YELLOW% /\\${YELLOW}/g" \
        -e "s/ %BLUE% /\\${BLUE}/g" \
        -e "s/ %MAGENTA% /\\${MAGENTA}/g" \
        -e "s/ %CYAN% /\\${CYAN}/g" \
        \
        -e "s/ %NORMAL% /\\${NORMAL}/g" \
        -e "s/$/\\${NORMAL}/g"
}

COLOUR_ARGS() {
    echo -e $(echo "$*" | COLOUR_STDIN)
}

INSTALL_TOOLS() {
    [ $USE_PV -eq 0 ] && return
    dpkg -l | grep -q " pv " || {
        echo "Installing pv tool ..."
        sudo apt-get install -qq -y pv
    }
}

KUBEADM_RESET() {
    which kubeadm 2>/dev/null || return

    DO_RESET=0
    [ -f /etc/kubernetes/ ]                && DO_RESET=1
    ps -fade | grep -v grep | grep -q kube && DO_RESET=1

    KUBEADM_RESET_FORCE=""
    [ $ALL_PROMPTS -eq 0 ] && KUBEADM_RESET_FORCE="--force"

    [ $DO_RESET -ne 0 ] && RUN sudo kubeadm reset $KUBEADM_RESET_FORCE
}

KUBE_REMOVE_DIRS() {
    REMOVE_DIRS=0
    [ -d /etc/kubernetes/ ] && REMOVE_DIRS=1
    [ -d /var/lib/etcd/ ]   && REMOVE_DIRS=1
    [ $REMOVE_DIRS -ne 0 ] && {
        STEP_HEADER "rm -rf /etc/kubernetes/ /var/lib/etcd/" " - remove config directories"
        RUN sudo rm -rf /etc/kubernetes/ /var/lib/etcd/
    }
}

SOFT_RESET_NODE() {
    STEP_HEADER "SOFT_RESET_NODE:"  " Resetting this node so that you can re-try kubeadm 'init' or 'join'"

    #STEP_HEADER "kubeadm reset" " - leave cluster and remove config directories"
    YESNO "kubeadm reset - leave cluster and remove config directories" "y" || exit 0

    KUBEADM_RESET
    KUBE_REMOVE_DIRS
}

HARD_RESET_NODE() {
    STEP_HEADER "HARD_RESET_NODE:"  " Resetting this node so that you can completely reinstall packages before kubeadm 'init' or 'join'"

    #STEP_HEADER "kubeadm reset" " - leave cluster and remove config directories"
    #set -x
    YESNO "kubeadm reset - leave cluster and remove config directories" "y" || exit 0
    KUBEADM_RESET
    KUBE_REMOVE_DIRS

    #STEP_HEADER "Remove packages/repo" " - unhold package versions; remove packages; remove repo kubernetes.list file"
    YESNO "Remove packages/repo - unhold package versions; remove packages; remove repo kubernetes.list file" "y" || exit 0

    #dpkg -l | grep "^ii " | grep -E " (kubeadm|kubelet|kubectl) " && {
    dpkg -l | grep -E " (kubeadm|kubelet|kubectl) " | grep "^[hi]i "
    PKGS_TO_REMOVE=$?
    if [ $PKGS_TO_REMOVE -ne 0 ]; then
        echo "... no Kubernetes packages to be removed"
    else
        RUN sudo apt-mark unhold kubectl kubeadm kubelet
        RUN sudo apt-get  remove -y kubectl kubeadm kubelet
    fi

    [ -f /etc/apt/sources.list.d/kubernetes.list ] &&
        RUN sudo rm       /etc/apt/sources.list.d/kubernetes.list

    case ${CONTAINER_ENGINE} in
        DOCKER) REMOVE_DOCKER;;
        CRIO)   REMOVE_CRIO;;
        *) die "TODO: ${CONTAINER_ENGINE}";;
    esac
}

REMOVE_CRIO() {
    RUN sudo apt-get remove -y cri-o cri-o-runc podman buildah
    RUN sudo apt autoremove -y

    [ -d /var/run/crio ] && RUN sudo rm -rf /var/run/crio
    sudo rm -rf /etc/apt/sources.list.d/devel:*libcontainers*
}

REMOVE_DOCKER() {
    #dpkg -l | grep "^[hi]i " | awk '($2 ~ /docker|containerd/) { print $2; }'
    #PKGS_TO_REMOVE=$?

    DOCKER_PACKAGES=$( dpkg -l | grep "^[hi]i " | awk '($2 ~ /docker|containerd|cri-o/) { print $2; }' )
    [ -z "$DOCKER_PACKAGES" ] && {
        echo "... no Docker packages to be removed"
        return
    }

    #YESNO "Remove Docker - remove packages; remove repo docker.list file" "y" || exit 0
    YESNO "Remove Docker - remove packages" "y" || exit 0

    RUN sudo apt-get  remove -y $DOCKER_PACKAGES

    [ -d /var/run/crio ] && RUN sudo rm -rf /var/run/crio
}

USAGE() {
    echo "Usage:"
    echo "    $0 [-c|-w] [-r|-R] [-i|-ki|-I] [-kr]"
    echo
    echo "Specify node role:"
    echo "    -c:     control node (master)"
    echo "    -k8scp: control node (using LFS458 naming)"
    echo "    -w:     worker node"
    echo
    echo "Reset actions:"
    echo "    -r: soft reset (undo kubeadm actions)"
    echo "    -R: hard reset (remove packages, package repo, undo kubeadm actions)"
    echo
    echo "Install actions:"
    echo "    -i: kubernetes package repo + packages"
    echo "    -I: kubernetes package repo + packages + kubeadm init"
    echo "   -ki: kubeadm init"
    echo "    -Q: QUICK RESET / UNINSTALL / INSTALL - ymmv"
    echo
    echo "Kubernetes release option: default uses $K8S_REL"
    echo "   -kr: <RELEASE> # e.g. -kr 1.21.1"
    echo "   -kl:           # Downloads latest stable release"
    echo
    echo "For a first installation on a control node:"
    echo "    $0 -c  # assumes -I"
    echo
    echo "For a first installation on a worker node:"
    echo "    $0 -w  # assumes -i"
    echo 
    echo "To reset after a failed installation:"
    echo "    $0 -r"
    echo 
    echo "To hard reset after a failed installation:"
    echo "    $0 -R"
    echo 
}

INSTALL_PKGS() {
    GET_NODE_INFO
    #echo "Installing Kubernetes release $K8S_REL"
    DEMO_HEADER "INSTALL_PKGS:"  "Add Docker & Kubernetes[$K8S_REL] package repositories & install packages"

    CLEANUP_DOCKER_CRIO
    [ -f /etc/apt/sources.list.d/cri-0.list ] &&
        sudo rm /etc/apt/sources.list.d/cri-0.list
    [ -f /etc/apt/sources.list.d/libcontainers.list ] &&
        sudo rm /etc/apt/sources.list.d/libcontainers.list

    # Install the chosen container engine:
    INSTALL_BASE_PKGS
    $INSTALL_CE

    STEP_HEADER "INSTALL_PKGS:"  "Download/install the GPG key used to sign the Kubernetes packages"
    RUN 'curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -'

    STEP_HEADER "INSTALL_PKGS:"  "Configure the (apt) package tool to add the Kubernetes package repository"
    [ -f /etc/apt/sources.list.d/kubernetes.list ] &&
        sudo rm /etc/apt/sources.list.d/kubernetes.list
    RUN 'echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list'

    STEP_HEADER "INSTALL_PKGS:"  "Update the list of packages to take into account the added Kubernetes repository"
    RUN sudo apt -qq update || die "apt update failed"

    STEP_HEADER "INSTALL_PKGS:"  "Install the Kubernetes packages kubeadm (installer), kubectl (client), kubelet (manages Docker)"
    RUN sudo apt-mark unhold kubectl kubeadm kubelet
    RUN sudo apt install -qq -y kubelet=$K8S_VERSION kubeadm=$K8S_VERSION kubectl=$K8S_VERSION 

    STEP_HEADER "INSTALL_PKGS:"  "'mark' the packages as held at their current version - prevent accidental upgrades"
    RUN sudo apt-mark hold kubelet kubeadm kubectl

    STEP_HEADER "INSTALL_PKGS:"  "Showing kubectl, kubeadm package versions"
    RUN kubectl version --client --short
    RUN kubeadm version

    STEP_HEADER "INSTALL_PKGS:"  "Switch off Linux swap - Kubernetes will manage it's memory"
    #RUN sudo sed -i '/ swap / s/^\\(.*\\)$/#\\1/g' /etc/fstab
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    RUN sudo swapoff -a

    STEP_HEADER "INSTALL_PKGS:"  "Package installation & configuration complete"
    [ "$NODE_ROLE" = "control"  ] && return

    echo "Now manually join this node to the cluster"
    echo "The command to use on this node was previously saved in"
    echo "    ~/tmp/run_on_worker_to_join.txt"
    echo "on the control node"
    echo
}

CONFIGURE_SYSCTL() {
    sudo modprobe overlay
    sudo modprobe br_netfilter

    sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

    sudo sysctl --system
}

INSTALL_BASE_PKGS() {
    #DEMO_HEADER "INSTALL_BASE_PKGS:"  "This step will add the Kubernetes package repository and install kubeadm/kubelet/kubectl packages"
    STEP_HEADER "INSTALL_BASE_PKGS:"  "Reread(update) the list of available packages"
    RUN sudo apt -qq update
    STEP_HEADER "INSTALL_BASE_PKGS:"  "Upgrading all packages to latest available versions"
    RUN sudo apt -qq -y upgrade
    # && sudo systemctl reboot

    #RUN sudo apt -qq update
    STEP_HEADER "INSTALL_BASE_PKGS:"  "Install packages necessary to pull packages over https"
    RUN sudo apt install -qq -y curl gnupg2 software-properties-common apt-transport-https ca-certificates vim git wget
}

INSTALL_DOCKER() {
    # Add repo and Install packages
    #STEP_HEADER "INSTALL_DOCKER:"  "Reread(update) the list of available packages"
    #STEP_HEADER "INSTALL_DOCKER:"  "Switch off Linux swap - Kubernetes will manage it's memory"
    #RUN sudo apt -qq update

    STEP_HEADER "INSTALL_DOCKER:"  "Download/install the GPG key used to sign the Docker packages"
    RUN 'curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -'

    STEP_HEADER "INSTALL_DOCKER:"  "Configure the (apt) package tool to add the Docker package repository"
    RUN 'sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"'

    STEP_HEADER "INSTALL_DOCKER:"  "Update the list of packages to take into account the added Docker repository"
    RUN sudo apt -qq update

    STEP_HEADER "INSTALL_DOCKER:"  "Install the packages containerd.io (container engine), docker-ce* (docker client and daemon)"
    RUN sudo apt install -y containerd.io docker-ce docker-ce-cli
    echo "Ignore possible Docker failures at this stage"
    CHECK_DOCKER_STARTED

    STEP_HEADER "INSTALL_DOCKER:"  "Configure Docker for Kubernetes"
    # Create required directories
    RUN sudo mkdir -p /etc/systemd/system/docker.service.d

    # Create daemon json config file
    echo "Configuring /etc/docker/daemon.json ..."
    sudo tee /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

    STEP_HEADER "INSTALL_DOCKER:"  "Start & enable Services"
    RUN sudo systemctl daemon-reload
    RUN sudo systemctl restart docker
    RUN sudo systemctl enable docker

    CHECK_DOCKER_STARTED

    STEP_HEADER "INSTALL_DOCKER:"  "Allow user '$USER' to use Docker'"
    echo "Note: you must then logout/login of all '$USER' sessions"
    RUN sudo usermod -aG docker $USER

    STEP_HEADER "INSTALL_DOCKER:"  "Show Docker version"
    RUN sudo docker --version

    STEP_HEADER "INSTALL_DOCKER:"  "Verify Docker interaction"
    #RUN sudo docker ps |
    LOOP=0
    while ! sudo docker ps 2>/dev/null; do
        let LOOP=LOOP+1
        echo "Loop$LOOP: Docker not started: sleeping then restarting ..."
        sleep 10
        RUN sudo systemctl restart docker
    done

    RUN sudo docker ps
    [ $? -ne 0 ] && ALWAYS_WARN_PROMPT "Docker doesn't seem to be started"
}

CHECK_DOCKER_STARTED() {
    sudo systemctl status docker | grep failed && {
        STEP_HEADER "INSTALL_DOCKER:"  "Re-starting Docker after failure"
        sleep 2
        RUN sudo systemctl start docker
    }

    sudo systemctl status docker | grep failed && {
        die "Docker install failed - try restarting using 'sudo systemctl start docker'"
    }

    echo "Docker is running OK"
}

INSTALL_CRIO() {
    STEP_HEADER "INSTALL_CRIO:"  "..."
    # Ensure you load modules
    sudo modprobe overlay
    sudo modprobe br_netfilter

    # Set up required sysctl params
    sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

    # Reload sysctl
    sudo sysctl --system

    NODE_N="control"
    case $NODE_ROLE in
        control) NODE_N="control";;
        *)       NODE_N="worker";;
    esac

    # TODO: make sure we get the correct IPv4 address:
    IP=$(hostname -i)
    grep "^$IP " /etc/hosts ||
        echo $(hostname -i) ${NODE_N}${NODE_NUM} | sudo tee -a /etc/hosts

    # Add repo

    set -x
    APT_FILE=/etc/apt/sources.list.d/cri-0.list
    REPO_1="deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$K8S_MIN_VERSION/$OS/ /"
    grep "$REPO_1" $APT_FILE ||
        echo $REPO_1 | sudo tee -a $APT_FILE

    # K8S_MIN_VERSION=${K8S_REL%.*}
    RELEASE_KEY_URL=http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$K8S_MIN_VERSION/$OS/Release.key
    curl -L $RELEASE_KEY_URL | sudo apt-key add -
      echo "RELEASE_KEY_URL='$RELEASE_KEY_URL'"
      echo "K8S_MIN_VERSION='$K8S_MIN_VERSION'"
      #die "K8S_MIN_VERSION='$K8S_MIN_VERSION'"

    REPO_2="deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /"
    APT_FILE2=/etc/apt/sources.list.d/libcontainers.list
    grep "$REPO_2" $APT_FILE2 ||
        echo $REPO_2 | sudo tee -a $APT_FILE2
    set +x
    #sudo apt -qq update
    RUN sudo apt-get update

    # Install CRI-O
    RUN sudo apt-get install -y cri-o cri-o-runc podman buildah

    # Fix if needed for https://github.com/containers/podman/issues/9363
    sudo sed -i 's/,metacopy=on//g' /etc/containers/storage.conf

    STEP_HEADER "INSTALL_CRIO:"  "Start & enable Services"
    RUN sudo systemctl daemon-reload
    sleep 5
    RUN sudo systemctl start  crio
    RUN sudo systemctl enable crio
    RUN sudo systemctl status crio | grep failed && {
        die "Docker install failed - try restarting using 'sudo systemctl start docker'"
    }

    echo "CRI-O is running OK"
}

INSTALL_CONTAINERD() {
    die "TODO"

    STEP_HEADER "INSTALL_CONTAINERD:"  "..."
    # Configure persistent loading of modules
    sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

    # Load at runtime
    sudo modprobe overlay
    sudo modprobe br_netfilter

    # Ensure sysctl params are set
    sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

    # Reload configs
    sudo sysctl --system

    # Install required packages
    sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates


    # Add Docker repo
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

    # Install containerd
    sudo apt -qq update
    sudo apt install -y containerd.io

    # Configure containerd and start service
    sudo mkdir -p /etc/containerd
    sudo su -
    containerd config default  /etc/containerd/config.toml

    # restart containerd
    STEP_HEADER "INSTALL_CONTAINERD:"  "Start & enable Services"
    RUN sudo systemctl restart containerd
    RUN sudo systemctl enable containerd
}

INSTALL_PKGS_INIT() {
    INSTALL_PKGS

    KUBEADM_INIT

    UNTAINT_CONTROL_NODE

    echo
    HAPPY_SAILING
}

HAPPY_SAILING() {
    cat <<EOF
[1;34m
                    (((((((((                  
               .(((((((((((((((((.             
           .((((((((((((&((((((((((((.         
       /((((((((((((((((@((((((((((((((((/     
      ((((((((((((((((((@((((((((((((((((((    
     *(((((##((((((@@@@@@@@@@@((((((%#(((((*   
     (((((((@@@(@@@@#((@@@((#@@@@(@@@(((((((   
    *(((((((((@@@@(((((@@@(((((@@@@(((((((((,  
    (((((((((@@@%@@@@((@@@((@@@@%@@@(((((((((  
   .(((((((((@@((((@@@@@@@@@@@((((@@(((((((((. 
   (((((((((&@@(((((@@@(((@@@(((((@@&((((((((( 
   (((((((((&@@@@@@@@@@#(#@@@@@@@@@@&((((((((( 
  ((((((@@@@@@@@(((((@@@@@@@(((((&@@@@@@@((((((
  (((((((((((%@@((((%@@@(@@@%((((@@&(((((((((((
   ((((((((((((@@@((@@%(((%@@((@@@(((((((((((( 
     (((((((((((#@@@@%(((((&@@@@#(((((((((((   
      /(((((((((((@@@@@@@@@@@@@(((((((((((/    
        (((((((((@@(((((((((((@@(((((((((      
          (((((((&(((((((((((((&(((((((        
           /(((((((((((((((((((((((((/         
             (((((((((((((((((((((((           
[0m
EOF

    STEP_HEADER "All done on the control node:"  "Happy sailing ..."
}

KUBEADM_INIT() {
    STEP_HEADER "INSTALL_INIT:"  "Use the kubeadm installer to initialize the cluster 1st node (Control)"

    STEP_HEADER "INSTALL_INIT:"  "Pre-pulling container images"
    RUN sudo kubeadm config images pull

    STEP_HEADER "INSTALL_INIT:"  "Initialize the cluster"
    echo "Note: --pod-network-cidr: specifies the subnet which will be used for Pod IP addresses"
    echo "Note: --apiserver-cert-extra-sans: will allow secured access via the specified address (useful for tunneled access)"
    #RUN sudo 'kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-cert-extra-sans 127.0.0.1 | tee ~/tmp/control.out'
    RUN sudo "kubeadm init --pod-network-cidr=$POD_CIDR --apiserver-cert-extra-sans 127.0.0.1 | tee ~/tmp/control.out"

    RUN sudo kubeadm config view | sudo tee /root/kubeadm-config.yaml
    # Extract join command:
    grep -A 1 "kubeadm join" ~/tmp/control.out | sed -e '1 s/^/sudo /' | tail -2 > ~/tmp/run_on_worker_to_join.txt

    STEP_HEADER "INSTALL_INIT:"  "Showing installed node"
    RUN sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes

    STEP_HEADER "INSTALL_INIT:"  "Creating 'kubeconfig' file for kubectl user as user '$USER'"
    RUN mkdir -p $HOME/.kube
    [ -f $HOME/.kube/config ] && cp -a $HOME/.kube/config $HOME/.kube/config.bak
    #RUN sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    RUN sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
    #RUN sudo chown $(id -u):$(id -g) $HOME/.kube/config
    RUN sudo chown -R $(id -u):$(id -g) $HOME/.kube/

    STEP_HEADER "INSTALL_INIT:"  "Showing installed node - as user $USER"
    RUN kubectl get nodes

    STEP_HEADER "INSTALL_INIT:"  "Install Calico networking plugin"
    # Keep local copy of calico.yaml:
    RUN wget -O ~/calico.yaml https://docs.projectcalico.org/manifests/calico.yaml
    RUN kubectl apply -f ~/calico.yaml

    # From: https://stackoverflow.com/questions/53198576/ansible-playbook-wait-until-all-pods-running
    
    ## Need to know Pod names but we don't know for calico-node-xxx ...
    STEP_HEADER "INSTALL_INIT:"  "Waiting for Calico Pods to be 'Created'"
    ## QRUN "kubectl get pods --namespace=kube-system --selector tier=control-plane --output=jsonpath='{.items[*].metadata.name}'"
    while ! kubectl get pods -n kube-system -o name | grep pod/calico-node ; do echo -n .; sleep 1; done
    while ! kubectl get pods -n kube-system -o name | grep pod/calico-kube ; do echo -n .; sleep 1; done
    echo

    STEP_HEADER "INSTALL_INIT:"  "Waiting for all Pods to be 'Running' - may take 1-2 mins"
    # QRUN kubectl wait --namespace=kube-system --for=condition=Ready pods --selector tier=control-plane --timeout=600s
    QRUN kubectl wait --namespace=kube-system --for=condition=Ready pods --all --timeout=600s

    #kubectl cluster-info
    #kubectl cluster-info dump
}

QUICK_RESET_UNINSTALL_REINSTALL() {
    #YESNO "Are you really sure you want to completely reset your cluster\n${RED}Warning:${NORMAL} You won't be asked again ..." || exit 0
    DEFAULT="n"
    [ $ALL_PROMPTS -eq 0 ] && DEFAULT="y"
    YESNO "Are you really sure you want to completely reset your cluster
        Warning: You won't be asked again ..." "$DEFAULT" || exit 0
    ALL_PROMPTS=0
    PV_RATE=100
    HARD_RESET_NODE

    [ "$NODE_ROLE" = "worker"  ] && INSTALL_PKGS
    [ "$NODE_ROLE" = "control" ] && INSTALL_PKGS_INIT
}

UNTAINT_CONTROL_NODE() {
    TAINT="node-role.kubernetes.io/master:NoSchedule"
    SELECTOR="-l node-role.kubernetes.io/control-plane"
    TAINT_KEY=${TAINT%:*}

    # Add taint for testing:
    # kubectl taint node node-role.kubernetes.io/master:NoSchedule -l node-role.kubernetes.io/control-plane
    # kubectl taint node $TAINT $SELECTOR

    STEP_HEADER "Checking for taint on control-plane nodes" " - remove taint if present"
    kubectl get nodes $SELECTOR -o custom-columns=NAME:metadata.name,TAINTS:spec.taints |
	    grep NoSchedule | grep ${TAINT_KEY} && {
        echo "Removing '$TAINT' taint from control-plane nodes:"
        CMD="kubectl taint node $SELECTOR ${TAINT_KEY}-"
	echo "-- $CMD"
	$CMD
        kubectl get nodes $SELECTOR -o custom-columns=NAME:metadata.name,TAINTS:spec.taints
    }
}

CHOOSE_CIDR() {
    # Adapt POD_CIDR range:
    # - detect if management network is 192.168.0.x, if so choose 192.168.128.0/18 as Pod subnet

    IP1=$( ip a|grep -A 4 ^2: | grep " inet " | sed -e 's/.* inet //' -e 's?/.*??' )
    IP_PART=${IP1%.*}
    [ "$IP_PART" = "192.168.0" ] && { POD_CIDR="192.168.128.0/18"; return; }

    IP2=$( hostname -i )
    IP_PART=${IP2%.*}
    [ "$IP_PART" = "192.168.0" ] && { POD_CIDR="192.168.128.0/18"; return; }
}

## Args: ------------------------------------------------------

ACTION=""

# echo -e "${GREEN}Hello world${NORMAL}" | PV
# exit

#HAPPY_SAILING; die "OK"

[ -z "$1" ] && {
    [ "$NODE" = "control" ] && set -- -I;
    [ "$NODE" = "worker"  ] && set -- -i;
}
[ -z "$1" ] && { USAGE; die "Missing options"; }

while [ ! -z "$1" ]; do
    case $1 in
        -x)   set -x;;
        +x)   set +x;;

       -set-nodename) shift; FORCE_NODENAME=$1;;

       -CP)   NODE="control"; ACTION="QUICK_RESET_UNINSTALL_REINSTALL";
              ABS_NO_PROMPTS=1; ALL_PROMPTS=0; PROMPTS=0;;

       -WO)   NODE="worker";  ACTION="QUICK_RESET_UNINSTALL_REINSTALL";
              ABS_NO_PROMPTS=1; ALL_PROMPTS=0; PROMPTS=0;;

       -ANP) ABS_NO_PROMPTS=1; ALL_PROMPTS=0; PROMPTS=0;;

       -anp|-NP) ALL_PROMPTS=0;;
       -np) PROMPTS=0;;
        -p) PROMPTS=1;;

        -R)   ACTION="HARD_RESET_NODE";;
        -r)   ACTION="SOFT_RESET_NODE";;

        -i)   ACTION="INSTALL_PKGS";;
        -I)   ACTION="INSTALL_PKGS_INIT";;
        -ki)  ACTION="KUBEADM_INIT";;

	# go faster stripes:
        -q)   PV_RATE=100;;
        -Q)   ACTION="QUICK_RESET_UNINSTALL_REINSTALL";;

        -kr) shift; K8S_REL="$1"; K8S_REL="${K8S_REL%-00}-00";;
        -kl) K8S_REL=$( curl -L -s https://dl.k8s.io/release/stable.txt )
             K8S_REL=${K8S_REL#v}
             K8S_REL=${K8S_REL#V}
             K8S_REL="${K8S_REL%-00}-00"
             ;;

	# LFS458: uses k8scp as control node name:
        lfs*|-lfs*|k8scp|-k8scp) SET_INSTALL_MODE LFS458;;
        lfd*|-lfd*)              SET_INSTALL_MODE LFD459;;
        control|-control|-c)   NODE="control"; NODE_ROLE="control";;
        worker|-worker|-w)     NODE="worker";  NODE_ROLE="worker";;
        -[0-9]) NODE_NUM=${1#-};;

        -h|-?)   USAGE; exit 0;;

        -info)   GET_NODE_INFO; exit;;

        *) echo "${RED}Unknown option${NORMAL} '$1'"
           USAGE; exit 1;
        ;;
    esac
    shift
done

## Main: ------------------------------------------------------

USERID=$(id -u)
[ $USERID -eq 0 ] && die "Run this script as non-root user (but with sudo capabilities)"

CHOOSE_CIDR

case $NODE in
    k8scp)   NODE_ROLE="control"; SET_NODENAME=k8scp ;;
    control) SET_NODENAME=control$NODE_NUM ;;
    worker)  SET_NODENAME=worker$NODE_NUM ;;
    *) die "Unknown node option '$NODE'";;
esac

DEFAULT="n"
[ $ALL_PROMPTS -eq 0 ] && DEFAULT="y"
YESNO "About to install Kubernetes $K8S_REL on this $NODE_ROLE node - OK" "$DEFAULT" || exit 1

HOSTNAME=$(hostname)

[ ! -z "$FORCE_NODENAME" ] && SET_NODENAME=$FORCE_NODENAME
[ $HOSTNAME != "$SET_NODENAME" ] && {
    hostname | grep -iq "^${SET_NODENAME}$" ||
        YESNO "Do you want to change hostname to be '$SET_NODENAME' before installing (recommended)" "y" &&
            sudo hostnamectl set-hostname $SET_NODENAME

    HOSTNAME=$(hostname)
}

#HAPPY_SAILING; die "OK"
INSTALL_TOOLS

case $ACTION in
    HARD_RESET_NODE) HARD_RESET_NODE; exit $?;;
    SOFT_RESET_NODE) SOFT_RESET_NODE; exit $?;;
esac

[ "$NODE_ROLE" = "worker"  ] && [ -z "$ACTION" ] && ACTION="INSTALL_PKGS"
[ "$NODE_ROLE" = "control" ] && [ -z "$ACTION" ] && ACTION="INSTALL_PKGS_INIT"

[ -z "$NODE_ROLE" ]   && die "Unset node role '\$NODE_ROLE' - use -c, -k8scp or -w options"
[ -z "$ACTION" ] && die "Unset action '\$ACTION'"

[ "$NODE_ROLE" = "worker"  ] && [ "$ACTION" = "INSTALL_PKGS_INIT" ] &&
    die "Invalid action '$ACTION' for a worker node"
#die "OK"

case $ACTION in
    HARD_RESET_NODE) HARD_RESET_NODE; exit $?;;
    SOFT_RESET_NODE) SOFT_RESET_NODE; exit $?;;

    QUICK_RESET_UNINSTALL_REINSTALL) QUICK_RESET_UNINSTALL_REINSTALL; exit $?;;

    INSTALL_PKGS)      INSTALL_PKGS;      exit $?;;
    INSTALL_PKGS_INIT) INSTALL_PKGS_INIT; exit $?;;
    KUBEADM_INIT)      KUBEADM_INIT;          exit $?;;

    *) die "Unknown action '$ACTION'";;
esac


INFO="
Now you can re-run
On the control node:
    bash ./k8sMaster.sh |& tee master.out

Or on the worker node:
    bash ./k8sSecond.sh |& tee worker.out
"



