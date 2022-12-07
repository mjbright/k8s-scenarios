#!/bin/bash

# NOTE: Automating the first part of a manual kubeadm-based Kubernetes install
#       make available to facilitate quick setup on nodes without scp access

# For initial LFS458 installation:
# - update INITIAL_RELEASE below (currently 1.24.1 for 1.25.1 training)
# - on cp     node: install_kubernetes_packages.sh cp
# - on worker node: install_kubernetes_packages.sh worker
#
# Prior to Exercise 16 - HA Cluster
# - on cp2    node: install_kubernetes_packages.sh cp2 -1.25.4
# - on cp3    node: install_kubernetes_packages.sh cp3 -1.25.4
#
# To Join cp2, cp3 as control-plane nodes
# - on cp:
#     CERT_KEY=$( sudo kubeadm init phase upload-certs --upload-certs | grep -v upload-certs )
#     JOIN_CMD=$( sudo kubeadm token create --print-join-command )
#     JOIN_CMD="sudo $JOIN_CMD --control-plane --certificate-key $CERT_KEY"
# - on cp2: $JOIN_CMD
# - on cp3: $JOIN_CMD


NODE_NAME=$1

INITIAL_RELEASE=1.24.1

NODE_NAME=k8scp
NODE_IP=$( hostname -I | awk '{ print $1; }' )

# Funcs: --------------------------------------------------

die() { echo "$(hostname) - $0: die - $*" >&2; exit 1; }
#exit 1

UPDATE_HOSTNAME_HOSTS() {
    
    HOSTNAME=$( hostname )
    case $HOSTNAME in
        *cp*) NODE_NAME=$HOSTNAME;;
    esac

    [ $(hostname) != "$NODE_NAME" ] && {
        echo; echo "Updating hostname to '$NODE_NAME':"
        sudo hostnamectl set-hostname $NODE_NAME

        hostname | grep "^$NODE_NAME$" || {
            hostname
            die "Failed to set hostname to '$NODE_NAME'"
        }

        # Verify that preserve_hostname is set to false ...
        sudo sed -i.bak 's/preserve_hostname: .*/preserve_hostname: false/' $( sudo grep -rl preserve_hostname: /etc/ )
        #/etc/cloud/cloud.cfg:preserve_hostname: false
    }

    grep " $NODE_NAME" /etc/hosts || {
        echo; echo "Adding hostname entry to /etc/hosts:"
        echo "$NODE_IP $NODE_NAME" | sudo tee -a /etc/hosts
    }
}

INSTALL_PACKAGES() {
    echo; echo "Installing base packages & containerd:"
    sudo apt-get update &&
    sudo apt-get upgrade -y &&
    sudo apt-get install -y vim jq &&
    sudo apt install -y curl apt-transport-https vim git wget gnupg2 \
        software-properties-common ca-certificates uidmap
    [ $? -ne 0 ] && die "Initial s/w packages installn failed"

    sudo swapoff -a &&
    sudo modprobe overlay &&
    sudo modprobe br_netfilter
    [ $? -ne 0 ] && die "Swap/modprobe step failed"
    
    cat << EOF | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

    sudo sysctl --system
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo apt install containerd -y ||
        die "Containerd installn step failed"

    echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" |
        sudo tee /etc/apt/sources.list.d/kubernetes.list

    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg |
        sudo apt-key add - ||
        die "Kubernetes packages gpg key installn step failed"
    
    echo; echo "Installing kubernetes packages (kubeadm,kubectl,kubelet)"
    sudo apt-get update && sudo apt-get install -y \
        kubeadm=${INITIAL_RELEASE}-00 kubelet=${INITIAL_RELEASE}-00 kubectl=${INITIAL_RELEASE}-00 ||
        die "Kubernetes packages installn step failed"

    sudo apt-mark hold kubeadm kubelet kubectl ||
        die "Kubernetes packages installn step failed"

    sudo apt-mark hold kubelet kubeadm kubectl ||
        die "Kubernetes packages hold step failed"

}

# Args: ---------------------------------------------------

while [ ! -z "$1" ]; do
    case $1 in
     -1.*) INITIAL_RELEASE=${1#-};;
        *) NODE_NAME=$1;;
    esac
    shift
done

#echo "NODE_NAME='$NODE_NAME'"
#echo "INITIAL_RELEASE='$INITIAL_RELEASE'"
#die "OK"

# Main: ---------------------------------------------------

UPDATE_HOSTNAME_HOSTS $NODE_NAME

INSTALL_PACKAGES

