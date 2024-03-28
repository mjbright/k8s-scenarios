#!/usr/bin/env bash

[ -z "$K8S_RELEASE" ] && K8S_RELEASE=v1.29

#KEY_URL="https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key"
#REPO_LINE="deb http://pkgs.k8s.io/core:/stable:/v1.29/deb/ /"
KEY_URL=https://pkgs.k8s.io/core:/stable:/${K8S_RELEASE}/deb/Release.key
#REPO_LINE="deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /"
REPO_LINE="deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_RELEASE}/deb/ /"

die() { echo "$0: die - $*" >&2; exit 1; }

[ $( id -un ) = "root" ] || die "Must be run as root [USER=$(id -un)"

## Func: --------------------------------------------------------------------------

DISABLE_SWAP() {
    echo; echo "Checking swap is disabled  ..."
    local SWAP=$( swapon --show )
    [ -z "$SWAP" ] && { echo "Swap not enabled"; return; }

    echo; echo "Disabling swap ..."
    swapoff -a
    sed -i.bak 's/.*swap.*//' /etc/fstab
}

CONFIG_SYSCTL() {
    echo; echo "Configuring sysctl parameters for kubernetes .."
    cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
    cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

    sysctl --all    > ~/tmp/sysctl.all.before
    sysctl --system > ~/tmp/sysctl.system.op 2>&1
    sysctl --all    > ~/tmp/sysctl.all.mid
    sysctl --load /etc/sysctl.d/99-kubernetes-cri.conf > ~/tmp/sysctl.load.op 2>&1
    sysctl --all 2>&1 | grep -E "^net.(bridge|ipv4)." > ~/tmp/sysctl.netparams
    sysctl --all 2>&1 > ~/tmp/sysctl.all.after

    mkdir -p ~/tmp/
    modprobe -c -C /etc/modules-load.d/containerd.conf 2>&1 | tee ~/tmp/containerd.conf.op
    modprobe overlay
    modprobe br_netfilter
}

INSTALL_KUBE_PRE_PKGS() {
    local PKGS="apt-transport-https ca-certificates curl gnupg-agent vim tmux jq software-properties-common"

    echo; echo "Performing apt-get update ..."
    apt-get update >/dev/null 2>&1
    echo; echo "Installing packages: $PKGS ..."
    apt-get install -y $PKFGS
}

INSTALL_KUBE_PKGS() {
    local PKGS="kubelet kubeadm kubectl"

    echo; echo "Obtaining Kubernetes package GPG key..."
    mkdir -p -m 755 /etc/apt/keyrings

    [ -f  /etc/apt/keyrings/kubernetes-apt-keyring.gpg ] &&
        rm /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    echo "curl -fsSL $KEY_URL | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
    curl -fsSL $KEY_URL |
	sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg ||
	die "Failed to add Kubernetes package key"

    echo; echo "Creating kubernetes.list apt sources file..."
    echo $REPO_LINE | sudo tee /etc/apt/sources.list.d/kubernetes.list

    echo; echo "Performing apt-get update ..."
    apt-get update >/dev/null 2>&1

    echo; echo "Installing packages: $PKGS ..."
    apt-get install -y $PKGS

    echo; echo "Marking packages as 'hold': $PKGS ..."
    apt-mark hold $PKGS
}

CREATE_JOIN_SCRIPT() {
    local OUT=/home/student/kubeadm-init.out
    local JSH=/home/student/kubeadm-join.sh

    [ ! -f $OUT ] && die "Missing init o/pp file $OUT"
    
    grep -A 1 "kubeadm join" $OUT | tail -2 > $JSH
    chmod +x $JSH

    echo; echo "Created script TO BE RUN ON WORKER:"
    set -x
    ls -al $JSH
    cat $JSH
    set +x
}

## Args: --------------------------------------------------------------------------

while [ -n "$1" ]; do
    case $1 in
        -j|--join) 
            CREATE_JOIN_SCRIPT
	    exit $?
	    ;;
	
        *) die "Unknown option '$1'";;
    esac
    shift
done


## Main: --------------------------------------------------------------------------

echo "Installing Kubernetes packages for release $K8S_RELEASE"

DISABLE_SWAP
CONFIG_SYSCTL

echo "Checking Docker is available:"
sudo docker --version || die "Docker not accessible"

INSTALL_KUBE_PRE_PKGS
INSTALL_KUBE_PKGS


