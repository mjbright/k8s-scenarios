#!/usr/bin/env bash

# By default install docker, not just containerd:
INSTALL_DOCKER=${INSTALL_DOCKER:-1}

# Based on https://docs.docker.com/engine/install/
# - dropped ansible due to 'NoneType' errors !!

HOST=$( hostname )

## == Func: ======================================================================

die() { echo "$0: die - $*" >&2; exit 1; }

ARCH=$(uname -m)

case $ARCH in
    # multipass on Mac-M1:
    aarch64) echo "CPU Architecture: Arm64";;
     x86_64) echo "CPU Architecture: Amd64";;

    *) die "Not implemented for architecture '$ARCH'";;
esac

CLEAN() {
    echo; echo "== [$HOST] ==== Removing Docker Packages, Key & Repo"

    PKGS=""
    for PKG in docker.io docker-compose docker-compose-v2 docker-doc podman-docker; do
	dpkg -l | grep "^ii *$PKG " && PKGS+=" $PKG"
    done

    [ ! -z "$PKGS" ] && {
        echo "Packages to remove: '$PKGS'"
        sudo apt-get remove -y $PKGS
    }

    [ -f /etc/apt/keyrings/docker.gpg        ] &&
      sudo rm /etc/apt/keyrings/docker.gpg
    [ -f /etc/apt/sources.list.d/docker.list ] &&
      sudo rm /etc/apt/sources.list.d/docker.list
}

ADD_DOCKER_REPO() {
    [ -f /etc/apt/sources.list.d/docker.list ] && return

    echo; echo "== [$HOST] ==== Adding Docker Key"
    # Add Docker's official GPG key:
    {
      sudo apt-get update
      sudo apt-get install -y ca-certificates curl gnupg
      sudo install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      sudo chmod a+r /etc/apt/keyrings/docker.gpg
    } > ~/tmp/docker.keys.log 2>&1

    echo; echo "== [$HOST] ==== Adding Docker Repo"
    # Add the repository to Apt sources:
    {
      echo \
        "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
         "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt-get update
    } > ~/tmp/docker.repo.log 2>&1
}

INSTALL_DOCKER() {
    if [ $INSTALL_DOCKER -ne 0 ]; then
        echo; echo "== [$HOST] ==== Installing Docker + Containerd"
        {
          sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        } > ~/tmp/docker.install.log 2>&1
        echo; echo "== [$HOST] ==== Configuring Docker"
        sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m"
    },
    "storage-driver": "overlay2"
}
EOF

    else 
        echo; echo "== [$HOST] ==== Installing Containerd"
        {
          sudo apt-get install -y containerd.io
        } > ~/tmp/containerd.install.log 2>&1
    fi

    # Configure to use containerd (not docker/cri-docker)
    # https://github.com/RX-M/classfiles/blob/master/k8s.sh
    {
      sudo cp /etc/containerd/config.toml /etc/containerd/config.bak
      sudo containerd config default | sudo tee /etc/containerd/config.toml
      sudo sed -i -e 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
      sudo systemctl restart containerd
    } > ~/tmp/containerd.k8s.log 2>&1
}

ENABLE_DOCKER_USERS() {
    USERS=$*
    [ $INSTALL_DOCKER -eq 0 ] && return 0

    echo; echo "== [$HOST] ==== Check Docker OK as root:"
    sudo docker ps

    for _USER in $USERS; do
        echo; echo "== [$HOST] ==== Check Docker OK as $_USER:"

        echo "-- sudo usermod -aG docker $_USER"
        sudo usermod -aG docker $_USER
        echo "[$_USER] docker ps"
        sudo -u $_USER -i docker ps
    done
}

## == Args: ======================================================================

if [ "$1" = "-cd" ]; then
    echo "Installing only Containerd (not Docker)"
    INSTALL_DOCKER=0
fi

## == Main: ======================================================================

CLEAN
ADD_DOCKER_REPO
INSTALL_DOCKER
[ $INSTALL_DOCKER -ne 0 ] && ENABLE_DOCKER_USERS ubuntu student

exit 0

