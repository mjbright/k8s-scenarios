#!/usr/bin/env bash

HOST=$(hostname)

export WORKERS=${WORKERS:-worker}

echo "$0: Operating on Nodes: [ cp, $( echo $WORKERS | sed -e 's/ /, /g' ) ]"

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
  for WORKER in $WORKERS; do
      echo "== [$WORKER] BEFORE - checking presence of Kubernetes packages"
      ssh $WORKER dpkg -l | grep ".i  *kube" >/dev/null 2>&1 && {
        echo "[$WORKER] Cleaning up ... Kubernetes"
        #set -x
        ssh $WORKER sudo kubeadm reset -f 2>&1 | sudo tee /root/tmp/reset.$WORKER.log >/dev/null
        ssh $WORKER sudo killall kube-apiserver kube-proxy >/dev/null 2>&1
        ssh $WORKER sudo rm -rf /var/lib/etcd/ /etc/kubernetes/
        ssh $WORKER sudo apt-mark unhold kubectl kubelet kubeadm >/dev/null 2>&1
        ssh $WORKER sudo apt-get remove -y kubectl kubelet kubernetes-cni kubeadm cri-tools containerd.io >/dev/null 2>&1
        #set +x
      }
  done

  echo "== [$HOST] BEFORE - checking presence of Docker packages"
  dpkg -l | grep -q ".i  *docker" 2>&1 && {
    echo "[cp] Cleaning up ... Docker"
    sudo apt-get remove -y $( dpkg -l | grep -i docker | awk '{ print $2; }' ) >/dev/null 2>&1
  }
  for WORKER in $WORKERS; do
      echo "== [$WORKER] BEFORE - checking presence of Docker packages"
      ssh $WORKER dpkg -l | grep -q ".i  *docker" 2>&1 && {
        echo "[$WORKER] Cleaning up ... Docker"
        ssh $WORKER sudo apt-get remove -y $( ssh $WORKER dpkg -l | grep -i docker | awk '{ print $2; }' ) >/dev/null 2>&1
      }
  done
    
  echo "== [cp] BEFORE - checking presence of Containerd packages"
  dpkg -l | grep -q ".i  *containerd" 2>&1 && {
    echo "[cp] Cleaning up ... Containerd"
    sudo apt-get remove -y $( dpkg -l | grep -i containerd | awk '{ print $2; }' ) >/dev/null 2>&1
  }
  for WORKER in $WORKERS; do
      echo "== [$WORKER] BEFORE - checking presence of Containerd packages"
      ssh $WORKER dpkg -l | grep -q ".i  *containerd" 2>&1 && {
        # Worker first based on cp node package names:
    
        echo "[$WORKER] Cleaning up ... Containerd"
        ssh $WORKER sudo apt-get remove -y $( ssh $WORKER dpkg -l | grep -i containerd | awk '{ print $2; }' ) >/dev/null 2>&1
      }
  done

  echo
  echo "== [cp]: Packages AFTER:"
  dpkg -l | grep -E "docker|kube|containerd"
  for WORKER in $WORKERS; do
      echo "== [$WORKER]: Packages AFTER:"
      ssh $WORKER dpkg -l | grep -E "docker|kube|containerd"
  done
}

DOWNLOAD_install_scripts() {
    wget --no-cache -qO ~/scripts/install_docker.sh \
        https://raw.githubusercontent.com/mjbright/k8s-scenarios/master/scripts/install_docker.sh
    wget --no-cache -qO ~/scripts/install_kube_packages.sh \
        https://raw.githubusercontent.com/mjbright/k8s-scenarios/master/scripts/install_kube_packages.sh

    chmod +x ~/scripts/*.sh

    for WORKER in $WORKERS; do
        scp ~/scripts/install_docker.sh ~/scripts/install_kube_packages.sh $WORKER:scripts/
    done
}

CHECK_sudo_ssh() {
    echo "Checking local sudo:"
    sudo ls /tmp >/dev/null 2>&1 || die "local sudo test failed"
    for WORKER in $WORKERS; do
        echo "Checking remote sudo: $WORKER"
        ssh $WORKER sudo ls /tmp >/dev/null 2>&1 || die "remote sudo test failed"
    done
}

INSTALL_cp_wo() {
    echo "WORKERS=$WORKERS [ env: $( env | grep WORKERS ) ]"
    #exit 0
    sudo ~/scripts/install_kube_packages.sh -A
}

## Args: --------------------------------------------------------------------------------

[ $( id -un ) = "root" ] && die "Run as non-root"

INSTALL_cp_wo=0

[ $# -eq 0 ] && set -- --clean-install

while [ $# -gt 0 ]; do
    case $1 in
             -c|--clean) CLEAN_ALL; exit $?;;
           -i|--install) INSTALL_cp_wo=1;;

        --clean-install) CLEAN_ALL; INSTALL_cp_wo=1;;

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

