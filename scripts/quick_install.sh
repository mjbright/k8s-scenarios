#!/usr/bin/env bash

## Func: --------------------------------------------------------------------------------

die() { echo "$0: die - $*" >&2; exit 1; }

CLEAN_ALL() {
  echo "Cleaning up any current Kubernetes/Docker/Containerd installation:"

  dpkg -l | grep ".i  *kube" >/dev/null 2>&1 && {
    echo "[cp] Cleaning up ... Kubernetes"
    set -x
    sudo kubeadm reset -f
    sudo killall kube-apiserver kube-proxy
    sudo rm -rf /var/lib/etcd/ /etc/kubernetes/
    sudo apt-mark unhold kubectl kubelet kubeadm
    sudo apt-get remove -y kubectl kubelet kubernetes-cni kubeadm cri-tools containerd.io >/dev/null 2>&1

    echo "[worker] Cleaning up ... Kubernetes"
    SSH sudo kubeadm reset -f
    SSH sudo killall kube-apiserver kube-proxy
    SSH sudo rm -rf /var/lib/etcd/ /etc/kubernetes/
    SSH sudo apt-mark unhold kubectl kubelet kubeadm
    SSH sudo apt-get remove -y kubectl kubelet kubernetes-cni kubeadm cri-tools containerd.io >/dev/null 2>&1
    set +x
  }

  dpkg -l | grep ".i  *docker" 2>&1 && {
    # Worker first based on cp node package names:
    echo "[worker] Cleaning up ... Docker"
    SSH sudo apt-get remove -y $( dpkg -l | grep -i docker | awk '{ print $2; }' ) >/dev/null 2>&1

    echo "[cp] Cleaning up ... Docker"
    sudo apt-get remove -y $( dpkg -l | grep -i docker | awk '{ print $2; }' ) >/dev/null 2>&1
  }

  dpkg -l | grep ".i  *containerd" 2>&1 && {
    # Worker first based on cp node package names:

    echo "[worker] Cleaning up ... Containerd"
    SSH sudo apt-get remove -y $( dpkg -l | grep -i containerd | awk '{ print $2; }' ) >/dev/null 2>&1

    echo "[cp] Cleaning up ... Containerd"
    sudo apt-get remove -y $( dpkg -l | grep -i containerd | awk '{ print $2; }' ) >/dev/null 2>&1
    }
}

DOWNLOAD_install_scripts() {
    wget -qO ~/scripts/install_docker.sh \
        https://raw.githubusercontent.com/mjbright/k8s-scenarios/master/scripts/install_docker.sh
    wget -qO ~/scripts/install_kube_packages.sh \
        https://raw.githubusercontent.com/mjbright/k8s-scenarios/master/scripts/install_kube_packages.sh

    chmod +x ~/scripts/*.sh

    scp ~/scripts/install_*.sh worker:scripts/
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

