#!/usr/bin/env bash

HOST=$(hostname)

## Func: --------------------------------------------------------------------------------

die() { echo "$0: die - $*" >&2; exit 1; }

CLEAN_ALL() {
  echo; echo "Cleaning up any current Kubernetes/Docker/Containerd installation:"

  echo; echo "== [$HOST] checking presence of Kubernetes packages"
  dpkg -l | grep ".i  *kube" >/dev/null 2>&1 && {
    echo; echo "[cp] Cleaning up ... Kubernetes"
    set -x
    sudo kubeadm reset -f
    sudo killall kube-apiserver kube-proxy
    sudo rm -rf /var/lib/etcd/ /etc/kubernetes/
    sudo apt-mark unhold kubectl kubelet kubeadm
    sudo apt-get remove -y kubectl kubelet kubernetes-cni kubeadm cri-tools containerd.io >/dev/null 2>&1
    set +x
  }
  echo; echo "== [worker] checking presence of Kubernetes packages"
  ssh worker dpkg -l | grep ".i  *kube" >/dev/null 2>&1 && {
    echo; echo "[worker] Cleaning up ... Kubernetes"
    set -x
    ssh worker sudo kubeadm reset -f
    ssh worker sudo killall kube-apiserver kube-proxy
    ssh worker sudo rm -rf /var/lib/etcd/ /etc/kubernetes/
    ssh worker sudo apt-mark unhold kubectl kubelet kubeadm
    ssh worker sudo apt-get remove -y kubectl kubelet kubernetes-cni kubeadm cri-tools containerd.io >/dev/null 2>&1
    set +x
  }

  echo; echo "== [$HOST] checking presence of Docker packages"
  dpkg -l | grep ".i  *docker" 2>&1 && {
    echo; echo "[cp] Cleaning up ... Docker"
    sudo apt-get remove -y $( dpkg -l | grep -i docker | awk '{ print $2; }' ) >/dev/null 2>&1
  }
  echo; echo "== [worker] checking presence of Docker packages"
  ssh worker dpkg -l | grep ".i  *docker" 2>&1 && {
    echo; echo "[worker] Cleaning up ... Docker"
    ssh worker sudo apt-get remove -y $( ssh worker dpkg -l | grep -i docker | awk '{ print $2; }' ) >/dev/null 2>&1
  }

  echo; echo "== [cp] checking presence of Containerd packages"
  dpkg -l | grep ".i  *containerd" 2>&1 && {
    echo; echo "[cp] Cleaning up ... Containerd"
    sudo apt-get remove -y $( dpkg -l | grep -i containerd | awk '{ print $2; }' ) >/dev/null 2>&1
  }
  echo; echo "== [worker] checking presence of Containerd packages"
  ssh worker dpkg -l | grep ".i  *containerd" 2>&1 && {
    # Worker first based on cp node package names:

    echo; echo "[worker] Cleaning up ... Containerd"
    ssh worker sudo apt-get remove -y $( ssh worker dpkg -l | grep -i containerd | awk '{ print $2; }' ) >/dev/null 2>&1
  }

  echo; echo "== [cp]:"
  dpkg -l | grep -E "docker|kube|containerd"
  echo; echo "== [worker]:"
  ssh worker dpkg -l | grep -E "docker|kube|containerd"
}

DOWNLOAD_install_scripts() {
    wget -qO ~/scripts/install_docker.sh \
        https://raw.githubusercontent.com/mjbright/k8s-scenarios/master/scripts/install_docker.sh
    wget -qO ~/scripts/install_kube_packages.sh \
        https://raw.githubusercontent.com/mjbright/k8s-scenarios/master/scripts/install_kube_packages.sh

    chmod +x ~/scripts/*.sh

    scp ~/scripts/install_docker.sh ~/scripts/install_kube_packages.sh worker:scripts/
}

CHECK_sudo_ssh() {
    echo; echo "Checking local sudo:"
    sudo ls /tmp >/dev/null 2>&1 || die "local sudo test failed"
    echo; echo "Checking remote sudo:"
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

