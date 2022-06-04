#!/bin/bash

#CRIO_PKGS="cri-o cri-o-runc cri-tools"
#KUBE_PKGS="kubeadm kubectl kubelet kubernetes-cni"
CRIO_PKGS="cri-o cri-o-runc podman buildah"
KUBE_PKGS="kubeadm kubectl kubelet"
KUBEADM_CONFIG=""

SCRIPT_VERSION_INFO=""

# Temporary removal of podman due to upstream conflicts:
APT_INSTALL_BUILDAH=0
APT_INSTALL_PODMAN=0
#APT_INSTALL_PODMAN=1
#APT_INSTALL_BUILDAH=1
[ $APT_INSTALL_PODMAN -eq 0 ] && {
    SCRIPT_VERSION_INFO+="\nManual installation of Podman"
    CRIO_PKGS=$( echo $CRIO_PKGS | sed 's/ *podman *//g' )
    #CRIO_PKGS="cri-o cri-o-runc buildah"
    PODMAN_VERSION="v3.4.2"
}
[ $APT_INSTALL_PODMAN -eq 0 ] && {
    SCRIPT_VERSION_INFO+="\nManual installation of Buildah"
    CRIO_PKGS=$( echo $CRIO_PKGS | sed 's/ *buildah *//g' )
}

echo "[APT_INSTALL_PODMAN=$APT_INSTALL_PODMAN APT_INSTALL_BUILDAH=$APT_INSTALL_BUILDAH] CRIO_PKGS='$CRIO_PKGS'"
#exit

SHOW_CALLER=1
#SHOW_CALLER=0

CONTAINER_ENGINE="CRIO"

FORCE_NODENAME=1

# NOTE: For cri-o installation follow instructions at:
#       https://github.com/cri-o/cri-o/blob/main/install.md#apt-based-operating-systems

#K8S_VERSION=1.23.4-00
#K8S_VERSION=1.24.0-00
K8S_VERSION=1.24.1-00
CRIO_VERSION=1.24

PV_RATE=40

mkdir -p ~/tmp/

LOGFILE=~/tmp/$(basename $0).log

echo; echo "-- Installing k8s $K8S_VERSION & CRI-O $CRIO_VERISON, logging to $LOGFILE"
echo -e "-- $SCRIPT_VERSION_INFO"
#exec &> >(tee -a "$LOGFILE")
exec &> >(tee "$LOGFILE")



## -- Funcs: ---------------------------------------------------------

die() {
    echo -e "${RED}$0: die - ${NORMAL}$*" >&2
    for i in 0 1 2 3 4 5 6 7 8 9 10;do
        CALLER_INFO=`caller $i`
        [ -z "$CALLER_INFO" ] && break
        echo "    Line: $CALLER_INFO" >&2
    done
    exit 1
}

REMOVE_PKGS() {
    #dpkg -l | grep -q kubeadm && { }
    ps -fade | grep -v grep |  grep -E "kubelet|kube-api|kube-sched|kube-proxy|apiserver-etcd" && {
        RUN sudo kubeadm reset --force
    }

    sudo apt-mark showhold | grep kubeadm && {
        RUN sudo apt-mark unhold kubeadm kubelet kubectl
    }

    dpkg -l kubeadm |& grep ^ii && {
        RUN sudo systemctl disable kubelet
        RUN sudo systemctl stop kubelet
        RUN sudo apt-get remove -y $KUBE_PKGS
    }
    dpkg -l kubeadm |& grep ^ii && die "Failed to remove kubeadm"

    [ -f /etc/kubernetes/ ] && RUN sudo rm -rf /etc/kubernetes/
    [ -f /var/lib/etcd/   ] && RUN sudo rm -rf /var/lib/etcd/

    dpkg -l kubernetes-cni |& grep ^ii && {
        RUN sudo apt-get remove -y kubernetes-cni
    }
    dpkg -l kubernetes-cni |& grep ^ii && die "Failed to remove kubernetes-cni"
    [ -d /opt/cni/bin ] && RUN sudo rm -rf /opt/cni/bin

    #dpkg -l | grep -q cri-o && {
    dpkg -l cri-o |& grep ^ii && {
        RUN sudo systemctl disable crio
        RUN sudo systemctl stop crio

        RUN sudo apt-get remove -y $CRIO_PKGS
    }
    dpkg -l cri-o |& grep ^ii && die "Failed to remove cri-o"

    [ -d /etc/cni/ ]      && RUN sudo rm -rf /etc/cni/
    [ -d /var/run/crio/ ] && RUN sudo rm -rf /var/run/crio/

    #[ -f /etc/sysctl.d/kubernetes.conf ] &&
        #RUN sudo rm /etc/sysctl.d/kubernetes.conf
    #[ -f /etc/apt/sources.list.d/crio.list ] &&
        #RUN sudo rm /etc/apt/sources.list.d/crio.list
    #[ -f /etc/apt/sources.list.d/kubernetes.list ] &&
        #RUN sudo rm /etc/apt/sources.list.d/kubernetes.list
    #[ -f /etc/apt/sources.list.d/libcontainers.list ] &&
        #RUN sudo rm /etc/apt/sources.list.d/libcontainers.list
    for __FILE in \
        /etc/sysctl.d/kubernetes.conf \
        /etc/apt/sources.list.d/backports.list \
        /etc/apt/sources.list.d/crio.list \
        /etc/apt/sources.list.d/kubernetes.list \
        /etc/apt/sources.list.d/libcontainers.list \
        /etc/apt/sources.list.d/.Release.key \
        \
    ; do
        [ -f $__FILE ] && RUN sudo rm $__FILE
    done

    #ls -altr /etc/apt/sources.list.d/
    #RUN sudo rm -f /etc/apt/sources.list.d/devel:kubic:libcontainers:*
    #ls -altr /etc/apt/sources.list.d/
    #sudo rm -f /etc/apt/sources.list.d/devel:kubic:libcontainers:*
    #ls -altr /etc/apt/sources.list.d/
    #RUN sudo rm -f /etc/apt/sources.list.d/devel\:kubic\:libcontainers:*
    #ls -altr /etc/apt/sources.list.d/
    #sudo rm -f /etc/apt/sources.list.d/devel\:kubic\:libcontainers:*
    sudo rm -f /etc/apt/sources.list.d/devel*
    ls -altr /etc/apt/sources.list.d/

    RUN sudo apt autoremove -y
}

APT_BASE() {
    RUN sudo apt-get update -qq &&
      RUN sudo apt-get upgrade -qq -y
    RUN sudo apt-get install -qq -y vim nano libseccomp2
}

LINUX_CONFIG() {
    sudo modprobe overlay
    sudo modprobe br_netfilter

    sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

    RUN sudo sysctl --system > ~/tmp/sysctl.op 2>&1
    sudo cat /proc/sys/net/ipv4/ip_forward | grep 1 ||
        die "Failed to update /proc/sys/net/ipv4/ip_forward"
}

SET_HOSTNAME() {
    SET_NODENAME=$1; shift

    #    set -x
    HOSTNAME=$(hostname)

    #[ ! -z "$FORCE_NODENAME" ] && SET_NODENAME=$FORCE_NODENAME
    #[ $HOSTNAME != "$SET_NODENAME" ] && {
        #echo "PRE-TEST: SET_HOSTNAME $HOSTNAME => $SET_NODENAME"
    #}
    #exit
    [ $HOSTNAME != "$SET_NODENAME" ] && {
        echo "SET_HOSTNAME $HOSTNAME => $SET_NODENAME"
        hostname | grep -iq "^${SET_NODENAME}$" ||
            YESNO "Do you want to change hostname to be '$SET_NODENAME' before installing (recommended)" "y" &&
                sudo hostnamectl set-hostname $SET_NODENAME

        HOSTNAME=$(hostname)
    }

    #IPV4s=$( hostname -i )
    IPV4s=$( ip -4 a | grep " inet " | grep -v 127.0.0.1  | awk '{ print $2; }' | grep -v /32 | sed 's?/.*??' )
    #ip -bri -4 a | awk '/ UP / { print $3 }'
    IPV4s=$( ip -bri -4 a | awk '/ UP / { FS="/"; $0=$3; print $1; }' )
    IPV4s=$( echo $IPV4s ) # Create string w/o linefeed
    #echo "IPV4s=$IPV4s"
    sudo sh -c "echo '$IPV4s $SET_NODENAME' >> /etc/hosts"
    echo "SET_HOSTNAME $SET_NODENAME"
    RUN cat /etc/hosts
    RUN hostname
}

SET_OS() {
    source /etc/os-release
    # NAME="Ubuntu"
    # VERSION="20.04.4 LTS (Focal Fossa)"
    # ID=ubuntu
    # ID_LIKE=debian
    # PRETTY_NAME="Ubuntu 20.04.4 LTS"
    # VERSION_ID="20.04"
    # HOME_URL="https://www.ubuntu.com/"
    # SUPPORT_URL="https://help.ubuntu.com/"
    # BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
    # PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-po
    # licies/privacy-policy"
    # VERSION_CODENAME=focal
    # UBUNTU_CODENAME=focal

    #export OS=xUbuntu_20.04
    export OS=xUbuntu_${VERSION_ID}
}

SET_REPOS() {

    # New with 1.24: libseccomp2 for cri-o-runc (part1)
    ## __FILE=/etc/apt/sources.list.d/backports.list
    ## echo 'deb http://deb.debian.org/debian buster-backports main' |
        ## sudo tee $__FILE
    ## [ ! -s $__FILE ] && die "File $__FILE is empty"
    ## [ ! -f $__FILE ] && die "File $__FILE is missing"

    ## RUN sudo apt-get update -qq ||
        ## RUN sudo apt-get update || die "apt-get update had errors"

    __FILE=/etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
    echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" |
        RUN sudo tee $__FILE
    [ ! -s $__FILE ] && die "File $__FILE is empty"
    [ ! -f $__FILE ] && die "File $__FILE is missing"

    __FILE=/etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.list
    echo "deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/ /" |
        RUN sudo tee $__FILE
    [ ! -s $__FILE ] && die "File $__FILE is empty"
    [ ! -f $__FILE ] && die "File $__FILE is missing"


    ## #Add repos and keys   
    ## __FILE=/etc/apt/sources.list.d/crio.list
    ## #echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/ /" |
    ## echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/ /" |
    ##     RUN sudo tee $__FILE
    ## [ ! -s $__FILE ] && die "File $__FILE is empty"
    ## [ ! -f $__FILE ] && die "File $__FILE is missing"

    ## __FILE=/etc/apt/sources.list.d/.Release.key
    ## curl -sL http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/Release.key |
    ##     RUN sudo tee $__FILE
    ## [ ! -s $__FILE ] && die "File $__FILE is empty"
    ## [ ! -f $__FILE ] && die "File $__FILE is missing"
        #sudo apt-key add -
    ## RUN sudo apt-key add /etc/apt/sources.list.d/.Release.key

    ## __FILE=/etc/apt/sources.list.d/libcontainers.list
    ## #echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" |
    ## echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" |
    ##     RUN sudo tee $__FILE
    ## [ ! -s $__FILE ] && die "File $__FILE is empty"
    ## [ ! -f $__FILE ] && die "File $__FILE is missing"

    # RUN sudo apt-get update -qq ||
        # RUN sudo apt-get update || die "apt-get update had errors"

    # New with 1.24: libseccomp2 for cri-o-runc (part2)
    #apt update
    ## RUN sudo apt install -y -t buster-backports libseccomp2
    ## ## RUN sudo apt update -y -t buster-backports libseccomp2

    # New with 1.24: cri-o
    ## __FILE=/etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
    ## echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" |
    ##     RUN sudo tee $__FILE
    ## [ ! -s $__FILE ] && die "File $__FILE is empty"
    ## [ ! -f $__FILE ] && die "File $__FILE is missing"

    ## __FILE="/etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:${CRIO_VERSION}.list"
    ## RUN sudo ls -al "$__FILE"
    ## RUN sudo rm "$__FILE"
    ## RUN sudo ls -al "$__FILE"
    ## echo "deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/ /" |
    ##     RUN sudo tee "$__FILE"
    ## [ ! -s "$__FILE" ] && die "File $__FILE is empty"
    ## [ ! -f "$__FILE" ] && die "File $__FILE is missing"

    RUN sudo mkdir -p /usr/share/keyrings

    __FILE=/usr/share/keyrings/libcontainers-archive-keyring.gpg
    [ -f $__FILE ] && sudo rm $__FILE
    curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key |
        RUN sudo gpg --dearmor -o $__FILE
    __FILE=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg

    [ -f $__FILE ] && sudo rm $__FILE
    curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/Release.key |
        RUN sudo gpg --dearmor -o $__FILE

    ## mkdir -p /usr/share/keyrings
    ## __FILE=/usr/share/keyrings/libcontainers-archive-keyring.gpg
    ## [ -f $__FILE ] && sudo rm $__FILE
    ## curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key |
        ## RUN sudo gpg --dearmor -o $__FILE
    ## [ ! -s $__FILE ] && die "File $__FILE is empty"
    ## [ ! -f $__FILE ] && die "File $__FILE is missing"

    ## __FILE=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg
    ## [ -f $__FILE ] && sudo rm $__FILE
    ## curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/Release.key |
    ##     RUN sudo gpg --dearmor -o $__FILE
    ## [ ! -s $__FILE ] && die "File $__FILE is empty"
    ## [ ! -f $__FILE ] && die "File $__FILE is missing"
    
    RUN sudo apt-get update -qq
}

INSTALL_CRIO() {
    RUN sudo apt-get install -qq -y $CRIO_PKGS ||
        die "Failed to install cri-o packages"
    #RUN apt-get install cri-o cri-o-runc
    sleep 3

    sudo sed -i 's/,metacopy=on//g' /etc/containers/storage.conf
    sleep 3

    RUN sudo systemctl daemon-reload
    RUN sudo systemctl enable crio
    RUN sudo systemctl start crio
    RUN sudo systemctl status crio

    sudo systemctl status cri-o | grep '(running)' || sleep 5
    sudo systemctl status cri-o | grep '(running)' ||
        die "cri-o not active"

    [ -S /var/run/crio/crio.sock ] ||
        die "No crio socket: /var/run/crio/crio.sock"
}

INSTALL_KUBE() {
    sudo sh -c "echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' >> /etc/apt/sources.list.d/kubernetes.list"

    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

    RUN sudo apt-get update -qq

    RUN sudo apt-mark unhold kubeadm kubelet kubectl
    RUN sudo apt-get install -qq -y kubeadm=${K8S_VERSION} kubelet=${K8S_VERSION} kubectl=${K8S_VERSION}
    RUN sudo apt-mark hold kubeadm kubelet kubectl
}

INSTALL_HELM() {
    HELM_VERSION=3.8.1
    RUN wget -qO /tmp/helm.tgz https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz
    tar xf /tmp/helm.tgz

    sudo mv linux-amd64/helm /usr/local/bin/
    sudo rm -rf linux-amd64

    RUN helm version
    echo
}

HAPPY_SAILING_TEST() {
   KEEP="$1"; shift

   TEST="test-$(( $RANDOM  % 100 ))"

   # Check taints:
   #kubectl taint node t-kube-2 node-role.kubernetes.io/master-
   kubectl describe nodes | grep Taints: | grep -v '<none>' | grep No &&
       die "Taint is still applied"

   # Create deployment & service:
   kubectl create deploy ${TEST} --image mjbright/k8s-demo:1 --replicas 3
   kubectl expose deploy ${TEST} --port 80

   #kubectl get pods -l app=${TEST} -o wide --no-headers | head -1
   kubectl rollout status deploy ${TEST}

   #kubectl get pods -l app=${TEST} -o wide --no-headers | head -1
   IP=$( kubectl get pods -l app=${TEST} -o wide --no-headers | head -1 | awk '{ print $6; exit; }')
   [ -z "$IP" ] && {
       kubectl get pods -l app=${TEST} -o wide
       die "Failed to get IP address for first pod"
   }

   echo; echo "Checking curl to first '${TEST}' Pod:"
   curl -sL $IP/1 | grep ^container ||
       die "Failed to curl to Pod at url $IP/1"

   SVC_IP=$( kubectl get svc ${TEST} --no-headers | awk '{ print $3; }' )
   echo; echo "Checking curl to '${TEST}' Service:"
   curl -sL $SVC_IP/1 | grep ^container ||
       die "Failed to curl to Pod at url $SVC_IP/1"

   curl -sL $SVC_IP

   [ "$KEEP" != "KEEP" ] && {
       echo "Cleaning up ${TEST} deployment & service:"
       kubectl delete svc/${TEST} deploy/${TEST}

       WORKER_NODE=$( grep -m 3 kube /etc/hosts | tail -1 | awk '{ print $2; }' )
       [ -z "$WORKER_NODE" ] && WORKER_NODE=worker

       echo
       CYAN "Remember to join the 2nd node"; echo
       CYAN "- scp ~/tmp/run_on_worker_to_join.txt $WORKER_NODE:"; echo
       CYAN "- ssh $WORKER_NODE sh -x ./run_on_worker_to_join.txt"; echo
       CYAN "- kubectl get nodes"; echo
   }

   echo
   STEP_HEADER "All done on the control node:"  "Happy sailing ..."
}

## -- Args: ----------------------------------------------------------

# READ OLD functions:
source ${0}.fn

HOST="cp"
ROLE="cp"
ABS_NO_PROMPTS=1; ALL_PROMPTS=0; PROMPTS=0

INSTALL_TOOLS

while [ ! -z "$1" ]; do
    case $1 in
        -x)   set -x;;
        +x)   set +x;;

       -aws) FORCE_NODENAME=1; HOST=$( curl -L  http://169.254.169.254/2009-04-04/meta-data/local-hostname )
          KUBEADM_CONFIG="/tmp/kubeadm_config.$$.yaml"
          CLUSTER_NAME="trainer-aws"
          cat > $KUBEADM_CONFIG <<EOF
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
apiServer:
  extraArgs:
    cloud-provider: external
clusterName: $CLUSTER_NAME
controllerManager:
  extraArgs:
    cloud-provider: external
kubernetesVersion: stable
networking:
  dnsDomain: cluster.local
  podSubnet: 192.168.0.0/16
  serviceSubnet: 10.96.0.0/12
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  name: $HOST
  kubeletExtraArgs:
    cloud-provider: external
EOF
           ;;

       -trace) SHOW_CALLER=1;;
       -set-nodename) shift; FORCE_NODENAME=$1;;

        # TODO: Fix to work with multiple control nodes:
       -CP)   NODE_ROLE="control";
              #ACTION="QUICK_RESET_UNINSTALL_REINSTALL";
              ABS_NO_PROMPTS=1; ALL_PROMPTS=0; PROMPTS=0;;

        # TODO: Fix to work with multiple workers:
       -WO)   NODE=worker; NODE_ROLE="worker"; 
              ACTION="QUICK_RESET_UNINSTALL_REINSTALL";
              ABS_NO_PROMPTS=1; ALL_PROMPTS=0; PROMPTS=0;;

       -ANP) ABS_NO_PROMPTS=1; ALL_PROMPTS=0; PROMPTS=0;;

       -anp|-NP) ALL_PROMPTS=0;;
       -np) PROMPTS=0;;
        -p) PROMPTS=1;;

        -U) UNTAINT_CONTROL_NODE; exit $?;;
        -C) INSTALL_CALICO; exit $?;;

       # -R)   ACTION="HARD_RESET_NODE";;
       # -r)   ACTION="SOFT_RESET_NODE";;

        # -i)   ACTION="INSTALL_PKGS";;
        # -I)   ACTION="INSTALL_PKGS_INIT";;
        # -ki)  ACTION="KUBEADM_INIT";;

        # go faster stripes:
        -q)   PV_RATE=100;;
        -Q)   ACTION="QUICK_RESET_UNINSTALL_REINSTALL";;

      -c) ROLE="cp";;
      -w) ROLE="worker"; HOST="worker";;

      -init) KUBEADM_INIT; exit;;
      -helm) INSTALL_HELM; exit;;
      -keep-sail) HAPPY_SAILING_TEST "KEEP"; exit;;
      -sail)      HAPPY_SAILING_TEST "CLEAN"; exit;;

      -R) HARD_RESET_NODE; exit;;

       *) die "Unknown option '$1'";;
    esac
    shift
done

## -- Main: ----------------------------------------------------------

REMOVE_PKGS
APT_BASE
LINUX_CONFIG
SET_HOSTNAME $HOST
SET_OS
SET_REPOS
INSTALL_CRIO
INSTALL_KUBE

[ $APT_INSTALL_PODMAN -eq 0 ] && {
    cd ~/tmp
    PODMAN_URL=https://github.com/mgoltzsche/podman-static/releases/download/$PODMAN_VERSION/podman-linux-amd64.tar.gz
    RUN wget $PODMAN_URL
    RUN tar xf podman-linux-amd64.tar.gz

    RUN sudo cp -a podman-linux-amd64/usr/local/bin/podman /usr/local/bin
    RUN which podman    # Should see /usr/local/bin/podman
    RUN podman version  # Should see version 3.4.2
    cd -
}

if [ "$ROLE" != "worker" ]; then
    KUBEADM_INIT;
    INSTALL_HELM
    UNTAINT_CONTROL_NODE
    INSTALL_CALICO
    echo
    HAPPY_SAILING_TEST "CLEAN"
    #HAPPY_SAILING
fi

exit 0

