#!/usr/bin/env bash

cd

mkdir -p ~/tmp

URL=https://github.com/containerd/nerdctl/releases/download/v2.0.0-beta.4/nerdctl-2.0.0-beta.4-linux-amd64.tar.gz

wget -qO ~/tmp/nerdctl.tgz $URL

#tar xf ~/tmp/nerdctl.tgz
tar xf ~/tmp/nerdctl.tgz nerdctl

sudo mv nerdctl /usr/local/bin/

nerdctl version

