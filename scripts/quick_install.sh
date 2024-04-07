#!/usr/bin/env bash

HOST=$(hostname)

## Func: --------------------------------------------------------------------------------

die() { echo "$0: die - $*" >&2; exit 1; }

CLEAN_ALL() {
  echo; echo "Cleaning up any current Kubernetes/Docker/Containerd installation:"

  echo "== [$HOST] BEFORE - checking presence of Kubernetes packages"
  dpkg -l | grep ".i  *kube" >/dev/null 2>&1 && {
    echo "[cp] Cleaning up ... Kubernetes"
    #set -x
    sudo mkdir -p /root/tmp/
    sudo kubeadm reset -f 2>&1 | sudo tee /root/tmp/reset.log >/dev/null

    sudo systemctl stop kubelet
    sudo systemctl stop docker
    sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
    sudo swapoff -a

    sudo killall kube-apiserver kube-proxy >/dev/null 2>&1
    sudo rm -rf /var/lib/etcd/ /etc/kubernetes/
    sudo apt-mark unhold kubectl kubelet kubeadm >/dev/null 2>&1
    sudo apt-get remove -y kubectl kubelet kubernetes-cni kubeadm cri-tools containerd.io >/dev/null 2>&1
    #set +x
  }
  echo "== [worker] BEFORE - checking presence of Kubernetes packages"
  ssh worker dpkg -l | grep ".i  *kube" >/dev/null 2>&1 && {
    echo "[worker] Cleaning up ... Kubernetes"
    #set -x
    ssh worker sudo kubeadm reset -f 2>&1 | sudo tee /root/tmp/reset.worker.log >/dev/null
    ssh worker sudo killall kube-apiserver kube-proxy >/dev/null 2>&1
    ssh worker sudo rm -rf /var/lib/etcd/ /etc/kubernetes/
    ssh worker sudo apt-mark unhold kubectl kubelet kubeadm >/dev/null 2>&1
    ssh worker sudo apt-get remove -y kubectl kubelet kubernetes-cni kubeadm cri-tools containerd.io >/dev/null 2>&1
    #set +x
  }

  echo "== [$HOST] BEFORE - checking presence of Docker packages"
  dpkg -l | grep -q ".i  *docker" 2>&1 && {
    echo "[cp] Cleaning up ... Docker"
    sudo apt-get remove -y $( dpkg -l | grep -i docker | awk '{ print $2; }' ) >/dev/null 2>&1
  }
  echo "== [worker] BEFORE - checking presence of Docker packages"
  ssh worker dpkg -l | grep -q ".i  *docker" 2>&1 && {
    echo "[worker] Cleaning up ... Docker"
    ssh worker sudo apt-get remove -y $( ssh worker dpkg -l | grep -i docker | awk '{ print $2; }' ) >/dev/null 2>&1
  }

  echo "== [cp] BEFORE - checking presence of Containerd packages"
  dpkg -l | grep -q ".i  *containerd" 2>&1 && {
    echo "[cp] Cleaning up ... Containerd"
    sudo apt-get remove -y $( dpkg -l | grep -i containerd | awk '{ print $2; }' ) >/dev/null 2>&1
  }
  echo "== [worker] BEFORE - checking presence of Containerd packages"
  ssh worker dpkg -l | grep -q ".i  *containerd" 2>&1 && {
    # Worker first based on cp node package names:

    echo "[worker] Cleaning up ... Containerd"
    ssh worker sudo apt-get remove -y $( ssh worker dpkg -l | grep -i containerd | awk '{ print $2; }' ) >/dev/null 2>&1
  }

  echo
  echo "== [cp]: Packages AFTER:"
  dpkg -l | grep -E "docker|kube|containerd"
  echo "== [worker]: Packages AFTER:"
  ssh worker dpkg -l | grep -E "docker|kube|containerd"
}

DOWNLOAD_install_scripts() {
    wget --no-cache -qO ~/scripts/install_docker.sh \
        https://raw.githubusercontent.com/mjbright/k8s-scenarios/master/scripts/install_docker.sh
    wget --no-cache -qO ~/scripts/install_kube_packages.sh \
        https://raw.githubusercontent.com/mjbright/k8s-scenarios/master/scripts/install_kube_packages.sh

    chmod +x ~/scripts/*.sh

    scp ~/scripts/install_docker.sh ~/scripts/install_kube_packages.sh worker:scripts/
}

CHECK_sudo_ssh() {
    echo "Checking local sudo:"
    sudo ls /tmp >/dev/null 2>&1 || die "local sudo test failed"
    echo "Checking remote sudo:"
    ssh worker sudo ls /tmp >/dev/null 2>&1 || die "remote sudo test failed"
}

INSTALL_cp_wo() {
    sudo ~/scripts/install_kube_packages.sh -A
}

## Args: --------------------------------------------------------------------------------

[ $( id -un ) = "root" ] && die "Run as non-root"

INSTALL_cp_wo=0

while [ $# -gt 0 ]; do
    case $1 in
        -c|--clean) CLEAN_ALL; exit $?;;
        -i|--install) INSTALL_cp_wo=1;;

        *) die "Unknown option: '$1'";;
    esac
    shift
done

## Main: --------------------------------------------------------------------------------

[ $INSTALL_cp_wo -ne 0 ] && {
    CHECK_sudo_ssh
    DOWNLOAD_install_scripts
    INSTALL_cp_wo
}

