#!/usr/bin/env bash

echo "==== $0 $* ========================================"

# Examples usage:
#
# "Standard" containerd based Kubernetes install:
# - on cp node
#   ./scripts/k8s-installer.sh -q -CP
# - on worker node:
#   ./scripts/k8s-installer.sh -q -w
#
# "Docker-based" Kubernetes install
# - on cp node:
#   ./scripts/k8s-installer.sh -q -D -CP
# - on worker node:
#   ./scripts/k8s-installer.sh -q -D -w

#CRIO_PKGS="cri-o cri-o-runc cri-tools"
#KUBE_PKGS="kubeadm kubectl kubelet kubernetes-cni"
CRIO_PKGS="cri-o cri-o-runc podman buildah"
KUBE_PKGS="kubeadm kubectl kubelet"
KUBEADM_CONFIG=""

[ "$1" = "-x"  ] && { set -x;  shift; }
[ "$1" = "-fn" ] && { set -xT; shift; }
set -T
#[ "$1" = "-fn" ] && { set -o functrace; shift; }

#K8S_VERSION=1.23.4-00
#K8S_VERSION=1.24.0-00
#K8S_VERSION=1.24.4-00
#CRIO_VERSION=1.24
#K8S_VERSION=1.25.2-00
#CRIO_VERSION=1.25
#K8S_VERSION=1.26.0-00
#CRIO_VERSION=1.26
#K8S_VERSION=1.27.3-00
#CRIO_VERSION=1.27
#K8S_VERSION=1.30.3-1.1
#CRIO_VERSION=1.30
K8S_VERSION=1.31.1-1.1
CRIO_VERSION=1.31
K8S_RELEASE=$( echo $K8S_VERSION | sed -e 's/\.[0-9]*-[0-9][0-9]$//' -e 's/\.[0-9]*-[0-9]\.[0-9]$//' )
echo "K8S_VERSION=$K8S_VERSION     K8S_RELEASE=${K8S_RELEASE}"
#exit

export DEBIAN_FRONTEND=noninteractive

shopt -s expand_aliases
alias apt-get='apt-get -o DPkg::Lock::Timeout=60'

HOSTNAME=$(hostname)

POD_CIDR="192.168.0.0/16"
CLUSTER_CIDR="10.96.0.0/12"

SCRIPT_VERSION_INFO=""

# LoadBalancer args to set via -lb option
#  -lb "<lb-dns>:<lb-ip>"
LB_ARGS=""

ARCH=$( uname -p )

#CONTAINER_ENGINE=CRIO
#CONTAINER_ENGINE=CONTAINERD
CONTAINER_ENGINE=DOCKER
CRIO_PKGS=""

INSTALL_PODMAN=1
[ "$CONTAINER_ENGINE" = "DOCKER" ] && INSTALL_PODMAN=0

# Temporary removal of podman due to upstream conflicts: containernetwork-plugins and kubernetes-cni
APT_INSTALL_BUILDAH=0
APT_INSTALL_PODMAN=0
#APT_INSTALL_PODMAN=1
#APT_INSTALL_BUILDAH=1
[ "$CONTAINER_ENGINE" = "DOCKER" ] && {
    APT_INSTALL_BUILDAH=0
    APT_INSTALL_PODMAN=0
}
[ $INSTALL_PODMAN -ne 0 ] && {
    [ $APT_INSTALL_PODMAN -eq 0 ] && {
        SCRIPT_VERSION_INFO+="\nManual installation of Podman"
        CRIO_PKGS=$( echo $CRIO_PKGS | sed 's/ *podman *//g' )
        #CRIO_PKGS="cri-o cri-o-runc buildah"
        #PODMAN_VERSION="v3.4.2"
        PODMAN_VERSION="v4.2.1"
    }
    [ $APT_INSTALL_PODMAN -eq 0 ] && {
        SCRIPT_VERSION_INFO+="\nManual installation of Buildah"
        CRIO_PKGS=$( echo $CRIO_PKGS | sed 's/ *buildah *//g' )
    }
}

echo "[APT_INSTALL_PODMAN=$APT_INSTALL_PODMAN APT_INSTALL_BUILDAH=$APT_INSTALL_BUILDAH] CRIO_PKGS='$CRIO_PKGS'"
#exit

die() { echo "$0: die - $*" >&2; exit 1; }

HELM_VERSION=3.9.3
# In case of manual downloads (podman, helm):
case $ARCH in
    x86_64)
       PODMAN_URL=https://github.com/mgoltzsche/podman-static/releases/download/$PODMAN_VERSION/podman-linux-amd64.tar.gz
       HELM_URL=https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz
       ;;
    aarch64)
       PODMAN_URL=https://github.com/mgoltzsche/podman-static/releases/download/$PODMAN_VERSION/podman-linux-arm64.tar.gz
       HELM_URL=https://get.helm.sh/helm-v${HELM_VERSION}-linux-arm64.tar.gz
       #https://github.com/helm/helm/releases/download/v3.9.3/helm-v3.9.3-darwin-arm64.tar.gz
       ;;
    *) die "Unknown architecture: $ARCH";;
esac

SHOW_CALLER=1
#SHOW_CALLER=0

FORCE_NODENAME=1

# NOTE: For cri-o installation follow instructions at:
#       https://github.com/cri-o/cri-o/blob/main/install.md#apt-based-operating-systems

case $CONTAINER_ENGINE in
    DOCKER)     CONTAINER_ENGINE_VERSION=latest;;
    CONTAINERD) CONTAINER_ENGINE_VERSION=latest;;
    CRIO)       CONTAINER_ENGINE_VERSION=$CRIO_VERSION;;
esac
echo; echo "-- [$0 $LINENO] Installing k8s [$K8S_VERSION] & $CONTAINER_ENGINE [ $CONTAINER_ENGINE_VERSION ], logging to $LOGFILE"

PV_RATE=40

mkdir -p ~/tmp/

LOGFILE=~/tmp/$(basename $0).log

echo -e "-- $SCRIPT_VERSION_INFO"
#exec &> >(tee -a "$LOGFILE")
exec &> >(tee "$LOGFILE")
#set -xT



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

CHECK_APT_LOCK_STATUS() {
    # https://serverfault.com/questions/221871/how-do-i-check-to-see-if-an-apt-lock-file-is-locked

    echo "--[$*] Checking dpkg lock status -------------"
    sudo lsof /var/lib/dpkg/lock
    ps -fade | grep " apt" | grep -v grep

    local LOOP=0
    while true; do
        let LOOP=LOOP+1
        echo "sudo flock --timeout 60 ... --close /var/lib/dpkg/lock apt-get ..."
        sudo flock --timeout 60 --exclusive --close /var/lib/dpkg/lock apt-get \
                   -y -o Dpkg::Options::="--force-confold" upgrade

        if [ $? -eq 0 ]; then
          return 0
        fi
        PID=$( sudo flock --timeout 60 --exclusive --close /var/lib/dpkg/lock apt-get \
                   -y -o Dpkg::Options::="--force-confold" upgrade |&
            grep It is held by process 10918 | sed 's/.* is held by process //' )
        [ ! -z "$PID" ] && pstree -aps $PID

        echo "[Loop $LOOP] Another process has f-locked /var/lib/dpkg/lock" 1>&2
        echo "sudo lsof /var/lib/dpkg/lock"
        sudo lsof /var/lib/dpkg/lock
        ps -fade | grep " apt" | grep -v grep
        sleep 5
    done
}

REMOVE_PKGS() {
    #dpkg -l | grep -q kubeadm && { }
    ps -fade | grep -v grep |  grep -E "kubelet|kube-api|kube-sched|kube-proxy|apiserver-etcd" && {
        RUN sudo kubeadm reset --force
    }

    CHECK_APT_LOCK_STATUS "rm"

    sudo apt-mark showhold | grep kubeadm && {
        RUN sudo apt-mark unhold kubeadm kubelet kubectl
    }

    dpkg -l kubeadm |& grep ^ii && {
        RUN sudo systemctl disable --now kubelet
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

    dpkg -l containerd |& grep ^ii && {
        RUN sudo systemctl disable --now containerd

        RUN sudo apt-get remove -y containerd.io
    }
    dpkg -l containerd |& grep ^ii && die "Failed to remove containerd"

    #dpkg -l | grep -q cri-o && {
    dpkg -l cri-o |& grep ^ii && {
        RUN sudo systemctl disable crio
        RUN sudo systemctl stop crio

        #RUN sudo apt-get remove -y $CRIO_PKGS
        RUN sudo apt-get remove -y cri-o cri-o-runc podman buildah
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

    RUN sudo apt-get autoremove -y
    RUN sudo apt-get --fix-broken install -y
}

APT_BASE() {
    CHECK_APT_LOCK_STATUS "base"

    RUN sudo apt-get update -qq &&
      RUN sudo apt-get upgrade -qq -y
    RUN_APT_GET_INSTALL vim nano libseccomp2 curl wget
}

LINUX_CONFIG() {
    sudo modprobe overlay
    sudo modprobe br_netfilter
    cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

    sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

    RUN sudo sysctl --system > ~/tmp/sysctl.op 2>&1
    sudo grep 1 /proc/sys/net/ipv4/ip_forward ||
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
        hostname | grep -iq "^${SET_NODENAME}$" /etc/hosts ||
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
    grep -q "$IPV4s $SET_NODENAME" /etc/hosts || {
        sudo sh -c "echo '$IPV4s $SET_NODENAME' >> /etc/hosts"
    }
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

SET_REPOS_CRIO() {
    die "SET_REPOS_CRIO - untested now"

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

    RUN sudo mkdir -p /usr/share/keyrings

    __FILE=/usr/share/keyrings/libcontainers-archive-keyring.gpg
    [ -f $__FILE ] && sudo rm $__FILE
    curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key |
        RUN sudo gpg --dearmor -o $__FILE
    __FILE=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg

    [ -f $__FILE ] && sudo rm $__FILE
    curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/Release.key |
        RUN sudo gpg --dearmor -o $__FILE

    CHECK_APT_LOCK_STATUS "repos_crio"

    RUN sudo apt-get update -qq
}

INSTALL_NERDCTL() {
    #wget -qO /tmp/nerdctl.tgz https://github.com/containerd/nerdctl/releases/download/v0.23.0/nerdctl-0.23.0-linux-amd64.tar.gz
    wget -qO /tmp/nerdctl.tgz https://github.com/containerd/nerdctl/releases/download/v1.0.0/nerdctl-1.0.0-linux-amd64.tar.gz
    ls -al /tmp/nerdctl.tgz
    tar tf /tmp/nerdctl.tgz
    tar xf /tmp/nerdctl.tgz nerdctl
    sudo mv nerdctl /usr/local/bin/
    sudo chmod +x /usr/local/bin/nerdctl
    ls -al /usr/local/bin/nerdctl
    sudo /usr/local/bin/nerdctl version
}

INSTALL_CONTAINERD() {
    # Some steps from: https://www.hostafrica.ng/blog/kubernetes/kubernetes-ubuntu-20-containerd/
    # Add Docker/Containerd GPG key:
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

    CHECK_APT_LOCK_STATUS "containerd"

    RUN sudo add-apt-repository "'deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable'"
    RUN sudo apt-get update
    RUN_APT_GET_INSTALL containerd.io

    sudo mkdir -p /etc/containerd
    sudo containerd config default | sudo tee /etc/containerd/config.toml
    #sudo sed -i.bak -e 's/SystemdCgroup.*/SystemdCgroup = true/' /etc/containerd/config.toml

    RUN sudo systemctl disable --now containerd
    RUN sudo systemctl enable --now containerd

    ps -ef | grep containerd
    INSTALL_NERDCTL
}

INSTALL_CRIO() {
    CHECK_APT_LOCK_STATUS "crio"

    RUN_APT_GET_INSTALL $CRIO_PKGS ||
        die "Failed to install cri-o packages '$CRIO_PKGS'"
    sleep 3

    sudo sed -i 's/,metacopy=on//g' /etc/containers/storage.conf
    sleep 3

    RUN sudo systemctl daemon-reload
    RUN sudo systemctl enable --now crio
    #RUN sudo systemctl start crio
    RUN sudo systemctl status crio

    sudo systemctl status cri-o | grep '(running)' || sleep 5
    sudo systemctl status cri-o | grep '(running)' ||
        die "cri-o not active"

    [ -S /var/run/crio/crio.sock ] ||
        die "No crio socket: /var/run/crio/crio.sock"
}

xxxx_OLD_INSTALL_KUBE_PKGS() {
    # read -p "About to install Kubernetes packages\nPress <enter>"
    sudo sh -c "echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' >> /etc/apt/sources.list.d/kubernetes.list"

    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

    CHECK_APT_LOCK_STATUS "kube"

    RUN sudo apt-get update -qq

    RUN sudo apt-mark unhold kubeadm kubelet kubectl
    RUN_APT_GET_INSTALL --allow-downgrades kubeadm=${K8S_VERSION} kubelet=${K8S_VERSION} kubectl=${K8S_VERSION}
    [ $? -ne 0 ] && {
         dpkg -l | grep -E " (kubeadm|kubelet|kubectl) " | grep ^iU &&
             die "Looks like kubeadm/kubelet/kubectl install failed"

         [ -z `which kubectl` ] && die "Looks like kubeadm/kubelet/kubectl install failed - kubectl missing"
         [ -z `which kubelet` ] && die "Looks like kubeadm/kubelet/kubectl install failed - kubelet missing"
         [ -z `which kubeadm` ] && die "Looks like kubeadm/kubelet/kubectl install failed - kubeadm missing"
    }
    RUN sudo apt-mark hold kubeadm kubelet kubectl
}

NEW_INSTALL_KUBE_PKGS() {
    local PKGS="kubelet kubeadm kubectl"

    K8S_KEY_URL=https://pkgs.k8s.io/core:/stable:/v${K8S_RELEASE}/deb/Release.key
    K8S_REPO_LINE="deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_RELEASE}/deb/ /"

    echo "== [$HOST] Obtaining Kubernetes package GPG key..."
    mkdir -p -m 755 /etc/apt/keyrings

    [ -f  /etc/apt/keyrings/kubernetes-apt-keyring.gpg ] &&
        sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    #echo "curl -fsSL $K8S_KEY_URL | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
	  sudo ls -al /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null
	  sudo rm  -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null
    curl -fsSL $K8S_KEY_URL |
	      sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg || {
            echo "Failed: curl -fsSL $K8S_KEY_URL"
	          die "Failed to add Kubernetes package key"
        }
	  sudo ls -al /etc/apt/keyrings/

    echo "== [$HOST] Creating kubernetes.list apt sources file..."
    echo $K8S_REPO_LINE | sudo tee /etc/apt/sources.list.d/kubernetes.list

    echo "== [$HOST] Performing apt-get update ..."
    RUN sudo apt-get update

    echo "== [$HOST] Installing packages: $PKGS ..."
    echo "#### sudo apt-get install -y kubeadm=1.30.3-1.1"
    PKGS_V=""; for PKG in $PKGS; do PKGS_V+=" $PKG=$K8S_VERSION"; done
    RUN sudo apt-get install -y $PKGS_V
    #apt-get install -y $PKGS >/dev/null 2>&1
    dpkg -l | grep "^ii.* kubeadm" || die "Failed to install kubeadm"
    dpkg -l | grep "^ii.* kubelet" || die "Failed to install kubelet"
    dpkg -l | grep "^ii.* kubectl" || die "Failed to install kubectl"

    echo "== [$HOST] Marking packages as 'hold': $PKGS ..."
    #echo "-- apt-mark hold $PKGS"
    apt-mark hold $PKGS >/dev/null 2>&1
}

INSTALL_KUBE() {
    [ "$CONTAINER_ENGINE" = "CONTAINERD" ] && INSTALL_CONTAINERD
    [ "$CONTAINER_ENGINE" = "DOCKER" ] && {
        # read -p "About to install Docker\nPress <enter>"
        # read -p "Temp disabled INSTALL_DOCKER"
        dpkg -l | grep "^ii *docker-ce " ||
            INSTALL_DOCKER
        # read -p "About to configure Containerd for Kubernetes\nPress <enter>"
        CONFIGURE_CONTAINERD_K8S
        #INSTALL_CRI_DOCKERD
    }

    #OLD_INSTALL_KUBE_PKGS - for < 1.28 ??
    #read -p "OK about to call NEW_INSTALL_KUBE_PKGS"
    NEW_INSTALL_KUBE_PKGS
}

INSTALL_HELM() {
    RUN wget -qO /tmp/helm.tgz $HELM_URL
    RUN tar xf /tmp/helm.tgz

    RUN sudo mv linux-amd64/helm /usr/local/bin/
    RUN sudo rm -rf linux-amd64

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
   CMD="curl -sL $IP/1"
   $CMD | grep "pod .*@$IP" ||
       die "Failed to curl to Pod at url $IP/1   [$CMD]"

   SVC_IP=$( kubectl get svc ${TEST} --no-headers | awk '{ print $3; }' )
   echo; echo "Checking curl to '${TEST}' Service:"
   CMD="curl -sL $SVC_IP/1"
   $CMD | grep "pod .*@" ||
       die "Failed to curl to Pod at url $SVC_IP/1    [$CMD]"

   curl -sL $SVC_IP
   kubectl get svc ${TEST}
   kubectl get pods -l app=${TEST} -o wide

   if [ "$KEEP" = "KEEP" ]; then
       #echo; echo "=================== KEEPing ====================="
       ABS_NO_PROMPTS=0 ALL_PROMPTS=1 PROMPTS=1 PRESS ""
   else
       #echo; echo "------------------- CLEANing ---------------------"
       echo; echo "Cleaning up ${TEST} deployment & service:"
       kubectl delete svc/${TEST} deploy/${TEST}

       WORKER_NODE=$( grep -m 3 kube /etc/hosts | tail -1 | awk '{ print $2; }' )
       [ -z "$WORKER_NODE" ] && WORKER_NODE=worker

       echo
       if [ `kubectl get no | wc -l` = "2" ]; then
           CYAN "Remember to join the 2nd node"; echo
           CYAN "- scp ~/tmp/run_on_worker_to_join.txt $WORKER_NODE:"; echo
           CYAN "- ssh $WORKER_NODE sh -x ./run_on_worker_to_join.txt"; echo
           CYAN "- kubectl get nodes"; echo
           sleep 1
       fi
   fi

   echo
   STEP_HEADER "All done on the control node:"  "Happy sailing ..."
}

INSTALL_PODMAN() {
    cd ~/tmp
    RUN wget -qO podman.tar.gz $PODMAN_URL
    RUN tar xf podman.tar.gz

    #RUN sudo rsync -av ~/tmp/podman-linux-amd64/ /
    RUN sudo rsync -av ~/tmp/podman-linux-amd64/usr/ /usr/
    RUN sudo rsync -av ~/tmp/podman-linux-amd64/etc/ /etc/
    #RUN sudo cp -a podman-linux-amd64/usr/local/bin/podman /usr/local/bin
    #RUN sudo cp -a podman-linux-amd64/usr/local/lib/*      /usr/local/lib/

    RUN which  podman     # Should see /usr/local/bin/podman
    RUN podman --version  # Should see version 3.4.2

    LFD459_ADD_LOCAL_REGISTRY
    cd -
}

LFD459_ADD_LOCAL_REGISTRY() {
    sudo mkdir -p /etc/containers/registries.conf.d/

    cat <<EOF | sudo tee -a /etc/containers/registries.conf.d/registry.conf
[[registry]]
location = "<YOUR-registry-IP-Here:5000"
insecure = true
EOF

}

# READ OLD functions:
source ${0}.fn

## -- Args: ----------------------------------------------------------

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
localAPIEndpoint:
  advertiseAddress: "k8slb"
  bindPort: 6443
clusterName: $CLUSTER_NAME
controllerManager:
  extraArgs:
    cloud-provider: external
kubernetesVersion: stable
networking:
  dnsDomain: cluster.local
  podSubnet: $POD_CIDR
  serviceSubnet: $CLUSTER_CIDR
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  name: $HOST
  kubeletExtraArgs:
    cloud-provider: external
EOF
           ;;

       -no-mgmt) DISABLE_HOSTS_HOSTNAME_MGMT; exit $?;;

       -lb) LB_ARGS="--control-plane-endpoint $2"; shift;;
       -trace) SHOW_CALLER=1;;
       -set-nodename) shift; FORCE_NODENAME=$1;;

        -D) CONTAINER_ENGINE=DOCKER;;
        -CD) CONTAINER_ENGINE=CONTAINERD;;
        -CR) CONTAINER_ENGINE=CRIO;;

        # TODO: Fix to work with multiple control nodes:
       -c|-CP)   NODE_ROLE="control";
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
        -calico) INSTALL_CALICO; exit $?;;

       # -R)   ACTION="HARD_RESET_NODE";;
       # -r)   ACTION="SOFT_RESET_NODE";;

        # -i)   ACTION="INSTALL_PKGS";;
        # -I)   ACTION="INSTALL_PKGS_INIT";;
        # -ki)  ACTION="KUBEADM_INIT";;

        # go faster stripes:
        -q)   PV_RATE=100;;
        -qq)   PV_RATE=200;;
        -Q)   ACTION="QUICK_RESET_UNINSTALL_REINSTALL";;

      -cp) ROLE="cp"
          case $HOSTNAME in
              *cp[1-9]) HOST="cp${HOSTNAME##*cp}"
          esac
          ;;
      -w|-wo) ROLE="worker"
          HOST="worker"
          case $HOSTNAME in
              *worker[1-9]) HOST="worker${HOSTNAME##*worker}"
          esac
          ;;
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

echo "==== [MAIN] HOST=$HOST CP_INIT=$CP_INIT NODE_ROLE=$NODE_ROLE ========================================"

case $NODE_ROLE in
    control)
         [ -f /var/.role.worker ] &&
             die "Already attempted worker install on $(hostname): sure you want to install as cp node -> remove /tmp/.role.worker first"
         sudo touch /var/.role.cp
         ;;
    worker)
         [ -f /var/.role.cp ] &&
             die "Already attempted cp install on $(hostname): sure you want to install as worker node -> remove /tmp/.role.cp first"
         sudo touch /var/.role.worker
         ;;
         *) die "Unknown NODE_ROLE '$NODE_ROLE'";;
esac

# START:
#read -p "OK to here(START): Press <enter>"
DISABLE_HOSTS_HOSTNAME_MGMT
REMOVE_PKGS
APT_BASE
LINUX_CONFIG
SET_HOSTNAME $HOST
SET_OS
#read -p "OK to here(post SET_OS): Press <enter>"

# Disable CRIO install:
[ "$CONTAINER_ENGINE" = "CRIO" ] && {
    SET_REPOS_CRIO
    INSTALL_CRIO
}

# Do this within INSTALL_KUBE:
# [ "$CONTAINER_ENGINE" = "CONTAINERD" ] && INSTALL_CONTAINERD

INSTALL_KUBE
#read -p "OK to here(post INSTALL_KUBE): Press <enter>"
[ $INSTALL_PODMAN -ne 0 ] && [ $APT_INSTALL_PODMAN -eq 0 ] && INSTALL_PODMAN
PRELOAD_USER_IMAGES

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

XXXXXX





