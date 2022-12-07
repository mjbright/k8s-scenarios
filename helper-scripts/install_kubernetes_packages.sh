#!/bin/bash

# NOTE: Automating the first part of a manual kubeadm-based Kubernetes install
#       make available to facilitate quick setup on nodes without scp access

NODE_NAME=$1

INITIAL_RELEASE=1.24.1
K8SCP_IP=192.168.0.100



die() { echo "$(hostname) - $0: die - $*" >&2; exit 1; }
#exit 1


[ $(hostname) != "$NODE_NAME" ] &&
    sudo hostnamectl set-hostname $NODE_NAME

hostname | grep "^$NODE_NAME$" || {
    hostname
    die "Failed to set hostname to '$NODE_NAME'"
}

grep k8scp /etc/hosts ||
    echo $K8SCP_IP k8scp | sudo tee -a /etc/hosts
    
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
    
sudo apt-get update && sudo apt-get install -y \
    kubeadm=${INITIAL_RELEASE}-00 kubelet=${INITIAL_RELEASE}-00 kubectl=${INITIAL_RELEASE}-00 ||
    die "Kubernetes packages installn step failed"

sudo apt-mark hold kubeadm kubelet kubectl ||
    die "Kubernetes packages installn step failed"

sudo apt-mark hold kubelet kubeadm kubectl ||
    die "Kubernetes packages hold step failed"

