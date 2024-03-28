#!/usr/bin/env bash

# Set defaults:
[ -z "$K8S_RELEASE"    ] && K8S_RELEASE=v1.29
[ -z "$CILIUM_RELEASE" ] && CILIUM_RELEASE=1.15.3

## # Note: Setting POD_CIDR range to avoid 192.168.1.0/24 (home lab):
## [ -z "$POD_CIDR"       ] && POD_CIDR="192.168.128.0/17"

#KEY_URL="https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key"
#REPO_LINE="deb http://pkgs.k8s.io/core:/stable:/v1.29/deb/ /"
KEY_URL=https://pkgs.k8s.io/core:/stable:/${K8S_RELEASE}/deb/Release.key
#REPO_LINE="deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /"
REPO_LINE="deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_RELEASE}/deb/ /"

KUBEADM_INIT_OUT=/home/student/kubeadm-init.out
JOIN_SH=/home/student/kubeadm-join.sh

die() { echo "$0: die - $*" >&2; exit 1; }

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
    echo; echo "Configuring modules for kubernetes .."
    cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
    cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

    echo; echo "Configuring sysctl parameters for kubernetes .."
    sysctl --all    > ~/tmp/sysctl.all.before 2>&1
    sysctl --system > ~/tmp/sysctl.system.op 2>&1
    sysctl --all    > ~/tmp/sysctl.all.mid 2>&1
    sysctl --load /etc/sysctl.d/99-kubernetes-cri.conf > ~/tmp/sysctl.load.op 2>&1
    sysctl --all 2>&1 | grep -E "^net.(bridge|ipv4)." > ~/tmp/sysctl.netparams
    sysctl --all 2>&1 > ~/tmp/sysctl.all.after

    echo; echo "Loading modules for kubernetes .."
    mkdir -p ~/tmp/
    { 
        modprobe -c -C /etc/modules-load.d/containerd.conf
        modprobe overlay
        modprobe br_netfilter
    } > ~/tmp/containerd.conf.op  2>&1
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
    [ ! -f $KUBEADM_INIT_OUT ] && die "Missing init o/pp file $KUBEADM_INIT_OUT"
    
    grep -A 1 "kubeadm join" $KUBEADM_INIT_OUT | tail -2 > $JOIN_SH
    chmod +x $JOIN_SH
    sudo chown student:student $JOIN_SH

    echo; echo "Created script TO BE RUN ON WORKER:"
    set -x
    ls -al $JOIN_SH
    cat $JOIN_SH
    set +x
}

INSTALL_CNI_CILIUM() {
    # Adapted from:
    #  https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/

    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)

    CLI_ARCH=amd64
    [ "$(uname -m)" = "aarch64" ] && CLI_ARCH=arm64

    curl -sL --fail --remote-name-all \
        https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
    sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
    sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
    rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

    cilium install --version $CILIUM_RELEASE
}

## Args: --------------------------------------------------------------------------

while [ -n "$1" ]; do
    case $1 in
        -cni|--cilium) INSTALL_CNI_CILIUM; exit $?  ;;
        -j|--join)     CREATE_JOIN_SCRIPT; exit $?  ;;
	
        *) die "Unknown option '$1'";;
    esac
    shift
done


## Main: --------------------------------------------------------------------------

echo "Installing Kubernetes packages for release $K8S_RELEASE"

[ $( id -un ) = "root" ] || die "Must be run as root [USER=$(id -un)"

DISABLE_SWAP
CONFIG_SYSCTL

echo "Checking Docker is available:"
sudo docker --version || die "Docker not accessible"

INSTALL_KUBE_PRE_PKGS
INSTALL_KUBE_PKGS


