
INSTALL_PODMAN() {
    cd ~/tmp
    wget -qO podman.tar.gz $PODMAN_URL
    tar xf podman.tar.gz

    sudo rsync -av ~/tmp/podman-linux-amd64/usr/ /usr/
    sudo rsync -av ~/tmp/podman-linux-amd64/etc/ /etc/

    which  podman     # Should see /usr/local/bin/podman
    podman --version  # Should see version 3.4.2

    ADD_LOCAL_REGISTRY
    cd -
}

ADD_LOCAL_REGISTRY() {
    sudo mkdir -p /etc/containers/registries.conf.d/

    cat <<EOF | sudo tee -a /etc/containers/registries.conf.d/registry.conf
[[registry]]
location = "<YOUR-registry-IP-Here:5000"
insecure = true
EOF
}

INSTALL_PODMAN

