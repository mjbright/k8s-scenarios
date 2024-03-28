#!/usr/bin/env bash

# Based on https://docs.docker.com/engine/install/
# - dropped ansible due to 'NoneType' errors !!

die() { echo "$0: die - $*" >&2; exit 1; }

ARCH=$(uname -m)

case $ARCH in
    # multipass on Mac-M1:
    aarch64) echo "CPU Architecture: Arm64";;
     x86_64) echo "CPU Architecture: Amd64";;

    *) die "Not implemented for architecture '$ARCH'";;
esac

CLEAN() {
    echo; echo "==== Removing Docker Packages, Key & Repo"

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

    echo; echo "==== Adding Docker Key & Repo"

    # Add Docker's official GPG key:
    sudo apt-get update
    sudo apt-get install ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Add the repository to Apt sources:
    echo \
        "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
       "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
}

INSTALL_DOCKER() {
    echo; echo "==== Installing Docker"
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

ENABLE_DOCKER_USERS() {
    USERS=$*

    echo; echo "==== Check Docker OK as root:"
    sudo docker version

    for _USER in $USERS; do
        echo; echo "==== Check Docker OK as $_USER:"

        sudo usermod -aG docker $_USER
        sudo -u $_USER -i docker version
    done
}

CLEAN
ADD_DOCKER_REPO
INSTALL_DOCKER
ENABLE_DOCKER_USERS ubuntu student



