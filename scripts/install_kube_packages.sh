#!/usr/bin/env bash

[ -z "$K8S_RELEASE" ] && K8S_RELEASE=v1.29
echo "Installing Kubernetes packages for release $K8S_RELEASE"

#KEY_URL="https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key"
#REPO_LINE="deb http://pkgs.k8s.io/core:/stable:/v1.29/deb/ /"
KEY_URL=https://pkgs.k8s.io/core:/stable:/${K8S_RELEASE}/deb/Release.key
#REPO_LINE="deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /"
REPO_LINE="deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_RELEASE}/deb/ /"

die() { echo "$0: die - $*" >&2; exit 1; }

[ $( id -un ) = "root" ] || die "Must be run as root [USER=$(id un)"

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

    sysctl --all > ~/tmp/sysctl.all.before
    sysctl --system
    sysctl --all > ~/tmp/sysctl.all.mid
    sysctl --load /etc/sysctl.d/99-kubernetes-cri.conf 
    sysctl --all | grep -E "^net.(bridge|ipv4)." > ~/tmp/sysctl.netparams
    sysctl --all > ~/tmp/sysctl.all.after

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



DISABLE_SWAP
CONFIG_SYSCTL

echo "Checking Docker is available:"
sudo docker --version || die "Docker not accessible"

INSTALL_KUBE_PRE_PKGS
INSTALL_KUBE_PKGS


exit

   - name: Add Kubernetes Key
     apt_key: $KEY_URL

   - name: Add Kubernetes Repository
     apt_repository: $REPO_LINE     mode: 0600

     apt-get update
     apt-get install -y kubeadm=${K8S_RELEASE}-00 kubectl=${K8S_RELEASE}-00 kubelet=${K8S_RELEASE}-00

   - name: Enable service kubelet, and enable persistently
     service: 
       name: kubelet
       enabled: yes

   - name: Reboot all the kubernetes nodes.
     # DISABLED
     when: false
     reboot:
      msg: "Reboot initiated by Ansible"
      connect_timeout: 5
      reboot_timeout: 3600
      pre_reboot_delay: 0
      post_reboot_delay: 30
      test_command: whoami


  #become_user: root
  gather_facts: yes
  connection: ssh
  tasks:

  - name: Pulling images required for setting up a Kubernetes cluster
    shell: kubeadm config images pull

  - name: Resetting kubeadm
    shell: |
        kubeadm reset -f
        pkill -9 kube-apiserver
        pkill -9 kube-proxy
        exit  0
    register: output
    ignore_errors: true

  - name: Initializing Kubernetes cluster
    shell: kubeadm init --apiserver-advertise-address=$(ip a |grep ens160|  grep 'inet ' | awk '{print $2}' | cut -f1 -d'/') --pod-network-cidr 10.244.0.0/16 --v=5
    register: myshell_output

  - debug: msg="{{ myshell_output.stdout }}"

  - name: Create .kube to home directory of master server
    file:
      path: /root/.kube
      state: directory
      mode: 0755

  - name: Copy admin.conf to user's kube config to master server
    copy:
      src: /etc/kubernetes/admin.conf
      dest: /root/.kube/config
      remote_src: yes

  - name: Create .kube to ubuntu home directory of master server
    file:
      path: /home/ubuntu/.kube
      state: directory
      mode: 0755
      owner: ubuntu
      group: ubuntu

  - name: Copy /root/.kube/config to /home/ubuntu/.kube/config on master server
    copy:
      src: /root/.kube/config
      dest: /home/ubuntu/.kube/config
      remote_src: yes
      owner: ubuntu
      group: ubuntu

  - name: Create .kube to student home directory of master server
    file:
      path: /home/student/.kube
      state: directory
      mode: 0755
      owner: student
      group: student

  - name: Copy /root/.kube/config to /home/student/.kube/config on master server
    copy:
      src: /root/.kube/config
      dest: /home/student/.kube/config
      remote_src: yes
      owner: student
      group: student

  #- name: Copy admin.conf to user's kube config to ansible local server
  #  become: yes
  #  become_method: sudo
  #  become_user: root
  #  fetch:
  #    src: /etc/kubernetes/admin.conf
  #    #dest: "{{ ansible_env.HOME }}/.kube/config"
  #    #dest: "/home/mjb/.kube/config"
  #    dest: "/home/student/.kube/config"
  #    flat: yes
       
  - name: Get the token for joining the nodes with Kubernetes master.
    shell: kubeadm token create  --print-join-command
    register: kubernetes_join_command
  
  - debug:
     msg: "{{ kubernetes_join_command.stdout_lines }}"

  - name: Copy K8s Join command to file in master
    copy:
     content: "{{ kubernetes_join_command.stdout_lines[0] }}"
     dest: "/tmp/kubernetes_join_command"

  - name: Copy join command from master to local ansible server
    fetch:
      src: "/tmp/kubernetes_join_command"
      dest: "/tmp/kubernetes_join_command"
      flat: yes

  - name: Install Pod network
    shell: kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    register: myshell_output

  - name: Copy the output to master file
    copy:
     content: "{{ myshell_output.stdout }}"
     dest: "/tmp/pod_network_setup.txt"

  - name: Copy network output from master to local ansible server
    fetch:
      src: "/tmp/pod_network_setup.txt"
      dest: "/tmp/pod_network_setup.txt"
      flat: yes


