#!/usr/bin/env bash

# Set defaults:
INSTALL_DOCKER=${INSTALL_DOCKER:-0}
INSTALL_CONTAINERD=${INSTALL_CONTAINERD:-0}
#K8S_RELEASE=${K8S_RELEASE:-v1.29}
K8S_RELEASE=${K8S_RELEASE:-v1.30}
CILIUM_RELEASE=${CILIUM_RELEASE:-1.15.3}

## echo "$0: WORKERS=$WORKERS"
export WORKERS=${WORKERS:-worker}
## echo "$0: WORKERS=$WORKERS"

SCRIPT_DIR=$( dirname $( readlink -f $0 ))

HOST=$(hostname)

mkdir -p ~/tmp/

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

SSH_KEYSCAN_WORKER() {
    echo "== [$HOST] Setting known hosts for root access to worker"
    mkdir -p /root/.ssh
    ssh-keygen -R worker                          >/dev/null 2>&1
    ssh-keyscan worker >> /root/.ssh/known_hosts 2>/dev/null
}

DISABLE_SWAP() {
    echo "== [$HOST] Checking swap is disabled  ..."
    local SWAP=$( swapon --show )
    [ -z "$SWAP" ] && { echo "Swap not enabled"; return; }

    echo "== [$HOST] Disabling swap ..."
    swapoff -a
    sed -i.bak 's/.*swap.*//' /etc/fstab
}

CONFIG_SYSCTL() {
    echo "== [$HOST] Configuring modules for kubernetes .."
    cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf >/dev/null
overlay
br_netfilter
EOF
    cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

    echo "== [$HOST] Configuring sysctl parameters for kubernetes .."
    sysctl --all    > ~/tmp/sysctl.all.before 2>&1
    sysctl --system > ~/tmp/sysctl.system.op 2>&1
    sysctl --all    > ~/tmp/sysctl.all.mid 2>&1
    sysctl --load /etc/sysctl.d/99-kubernetes-cri.conf > ~/tmp/sysctl.load.op 2>&1
    sysctl --all 2>&1 | grep -E "^net.(bridge|ipv4)." > ~/tmp/sysctl.netparams
    sysctl --all 2>&1 > ~/tmp/sysctl.all.after

    echo "== [$HOST] Loading modules for kubernetes .."
    { 
        modprobe -c -C /etc/modules-load.d/containerd.conf
        modprobe overlay
        modprobe br_netfilter
    } > ~/tmp/containerd.conf.op  2>&1
}

INSTALL_NERDCTL() {
    URL=https://github.com/containerd/nerdctl/releases/download/v2.0.0-beta.4/nerdctl-2.0.0-beta.4-linux-amd64.tar.gz

    wget -qO ~/tmp/nerdctl.tgz $URL

    #tar xf ~/tmp/nerdctl.tgz
    tar xf ~/tmp/nerdctl.tgz nerdctl

    sudo mv nerdctl /usr/local/bin/

    nerdctl version
}

INSTALL_KUBE_PRE_PKGS() {
    local PKGS="apt-transport-https ca-certificates curl gnupg-agent vim tmux jq software-properties-common"

    echo "== [$HOST] Performing apt-get update ..."
    apt-get update >/dev/null 2>&1
    echo "== [$HOST] Installing packages: $PKGS ..."
    apt-get install -y $PKGS >/dev/null 2>&1
}

INSTALL_KUBE_PKGS() {
    local PKGS="kubelet kubeadm kubectl"

    echo "== [$HOST] Obtaining Kubernetes package GPG key..."
    mkdir -p -m 755 /etc/apt/keyrings

    [ -f  /etc/apt/keyrings/kubernetes-apt-keyring.gpg ] &&
        rm /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    #echo "curl -fsSL $KEY_URL | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
    curl -fsSL $KEY_URL |
	sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg ||
	die "Failed to add Kubernetes package key"

    echo "== [$HOST] Creating kubernetes.list apt sources file..."
    echo $REPO_LINE | sudo tee /etc/apt/sources.list.d/kubernetes.list

    echo "== [$HOST] Performing apt-get update ..."
    apt-get update >/dev/null 2>&1

    echo "== [$HOST] Installing packages: $PKGS ..."
    apt-get install -y $PKGS >/dev/null 2>&1

    echo "== [$HOST] Marking packages as 'hold': $PKGS ..."
    #echo "-- apt-mark hold $PKGS"
    apt-mark hold $PKGS >/dev/null 2>&1
}

CREATE_JOIN_SCRIPT() {
    [ ! -f $KUBEADM_INIT_OUT ] && die "Missing init o/pp file $KUBEADM_INIT_OUT"
    
    # Pickup just worker join command:
    grep -A 1 "kubeadm join" $KUBEADM_INIT_OUT | tail -2 > $JOIN_SH
    chmod +x $JOIN_SH
    sudo chown student:student $JOIN_SH

    echo "== [$HOST] Created script TO BE RUN ON WORKER:"
    set -x
    ls -al $JOIN_SH
    cat $JOIN_SH
    chown -R student:student $JOIN_SH
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

    # Run as student user to pickup ~/.kube/config:
    sudo -u student cilium install --version $CILIUM_RELEASE
}

HAPPY_SAILING_TEST() {
   KEEP="$1"; shift

   NUM_WORKERS=$( echo $WORKERS | wc -w )
   ## echo "NUM_WORKERS='$NUM_WORKERS'"
   let REPLICAS="3*(1 + $NUM_WORKERS)"
   ## echo "REPLICAS='$REPLICAS'"

   TEST="test-$(( $RANDOM  % 100 ))"

   # Check taints:
   #kubectl taint node t-kube-2 node-role.kubernetes.io/master-
   sudo -u student kubectl describe nodes | grep Taints: | grep -v '<none>' | grep No &&
       die "Taint is still applied"

   # Create deployment & service:
   sudo -u student kubectl create deploy ${TEST} --image mjbright/k8s-demo:1 --replicas $REPLICAS
   sudo -u student kubectl expose deploy ${TEST} --port 80

   #kubectl get pods -l app=${TEST} -o wide --no-headers | head -1
   sudo -u student kubectl rollout status deploy ${TEST}

   #kubectl get pods -l app=${TEST} -o wide --no-headers | head -1
   IP=$( sudo -u student kubectl get pods -l app=${TEST} -o wide --no-headers | head -1 | awk '{ print $6; exit; }')
   [ -z "$IP" ] && {
       sudo -u student kubectl get pods -l app=${TEST} -o wide
       die "Failed to get IP address for first pod"
   }

   echo; echo "== [$HOST] Checking curl to first '${TEST}' Pod:"
   CMD="curl -sL $IP/1"
   $CMD | grep "pod .*@$IP" ||
       die "Failed to curl to Pod at url $IP/1   [$CMD]"

   SVC_IP=$( sudo -u student kubectl get svc ${TEST} --no-headers | awk '{ print $3; }' )
   echo; echo "== [$HOST] Checking repeated curls to '${TEST}' Service:"
   CMD="curl -sL $SVC_IP/1"
   for I in $( seq $REPLICAS ); do
       $CMD | grep "pod .*@" ||
           die "Failed to curl to Pod at url $SVC_IP/1    [$CMD]"
    done

   curl -sL $SVC_IP
   sudo -u student kubectl get svc ${TEST}
   sudo -u student kubectl get pods -l app=${TEST} -o wide

   if [ "$KEEP" = "KEEP" ]; then
       #echo "== [$HOST] =================== KEEPing ====================="
       ABS_NO_PROMPTS=0 ALL_PROMPTS=1 PROMPTS=1 PRESS ""
   else
       #echo "------------------- CLEANing ---------------------"
       echo "== [$HOST] Cleaning up ${TEST} deployment & service:"
       sudo -u student kubectl delete svc/${TEST} deploy/${TEST}

       WORKER_NODE=$( grep -m 3 kube /etc/hosts | tail -1 | awk '{ print $2; }' )
       [ -z "$WORKER_NODE" ] && WORKER_NODE=worker

       echo
       if [ `sudo -u student kubectl get no | wc -l` = "2" ]; then
           echo "Remember to join the 2nd node"
           echo "- scp ~/tmp/run_on_worker_to_join.txt $WORKER_NODE:"
           echo "- ssh $WORKER_NODE sh -x ./run_on_worker_to_join.txt"
           echo "- kubectl get nodes"
           sleep 1
       fi
   fi

   echo
   echo "All done on the control node:"  "Happy sailing ..."
}

INSTALL_KUBE() {
    DISABLE_SWAP
    CONFIG_SYSCTL
    
    echo "Checking Docker is available:"
    sudo docker --version || die "Docker not accessible"
    INSTALL_NERDCTL

    INSTALL_KUBE_PRE_PKGS
    INSTALL_KUBE_PKGS
}

ALL() {
    [ $INSTALL_DOCKER -ne 0 ] && $SCRIPT_DIR/install_docker.sh
    [ $INSTALL_CONTAINERD -ne 0 ] && die "Not inmplemented - TODO: just add option to install_docker"

    SSH_KEYSCAN_WORKER
    INSTALL_KUBE
    ps aux | grep kube | grep -v grep | grep -v install_kube_packages.sh

    echo
    KUBEADM_INIT

    while kubectl get no cp | grep NotReady; do
        echo; echo "==kubectl wait no cp --for=condition=Ready"
        sudo -u student kubectl wait no cp --for=condition=Ready
    done

    echo; echo "== sudo -u student kubectl get no"
    sudo -u student kubectl get no
    sudo -u student kubectl get no | grep "cp " || die "Node init failed"

    echo; INSTALL_CNI_CILIUM
    echo; CREATE_JOIN_SCRIPT
    UNTAINT_NODES

    echo; echo "== Installing Docker/Kubernetes on worker Nodes: $WORKERS"
    for WORKER in $WORKERS; do
        echo "== checking connectivity to $WORKER node"
        sudo -u student ssh -o ConnectTimeout=1 $WORKER uptime || {
            echo "ssh to $WORKER not configured - stopping here"
        }

        sudo -u student scp $JOIN_SH $WORKER:/tmp/join.sh
        sudo -u student ssh -q $WORKER $SCRIPT_DIR/install_docker.sh
        sudo -u student ssh -q $WORKER sudo $0
        sudo -u student ssh -q $WORKER sudo sh -x /tmp/join.sh

        echo; echo "== Waiting for Node to be Ready ..."
        while sudo -u student kubectl get nodes | grep -q NotReady; do
            echo -n "."
            sleep 5
        done
        echo
        sudo -u student kubectl get nodes
    done
}

KUBEADM_INIT() {
    local INIT_CMD="kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket unix:///var/run/containerd/containerd.sock"

    #kubeadm init --pod-network-cidr=192.168.0.0/16 2>&1 | tee /tmp/kubeadm-init.op.$$ | tee $KUBEADM_INIT_OUT

    echo; echo "== $INIT_CMD    [output saved to $KUBEADM_INIT_OUT]"
    $INIT_CMD 2>&1 | tee /tmp/kubeadm-init.op.$$ > $KUBEADM_INIT_OUT

    echo "== Copying admin.conf to /home/student/.kube/config"
    mkdir -p /home/student/.kube/
    cp /etc/kubernetes/admin.conf /home/student/.kube/config
    chown -R student:student /home/student/.kube/
}

UNTAINT_NODES() {
    echo "== Untainting cp Node"
    sudo -u student kubectl taint node --all node-role.kubernetes.io/control-plane- >/dev/null 2>&1
}

## Args: --------------------------------------------------------------------------

while [ -n "$1" ]; do
    case $1 in
        -A|--all)      INSTALL_DOCKER=1; ALL; exit $?;;
        -d|--docker)   INSTALL_DOCKER=1;;
        -cd|--containerd) INSTALL_CONTAINERD=1;;
        -cni|--cilium) INSTALL_CNI_CILIUM; exit $?  ;;
        -j|--join)     CREATE_JOIN_SCRIPT; exit $?  ;;
        -keep-sail)    HAPPY_SAILING_TEST "KEEP"; exit;;
        -sail)         HAPPY_SAILING_TEST "CLEAN"; exit;;

	
        *) die "Unknown option '$1'";;
    esac
    shift
done


## Main: --------------------------------------------------------------------------

echo "$0: Operating on Nodes: [ cp, $( echo $WORKERS | sed -e 's/ /, /g' ) ]"

echo "Installing Kubernetes packages for release $K8S_RELEASE"

[ $( id -un ) = "root" ] || die "Must be run as root [USER=$(id -un)]"

INSTALL_KUBE

