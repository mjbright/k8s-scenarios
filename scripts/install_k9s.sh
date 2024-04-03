#!/usr/bin/env bash

die() { echo "$0: die - $*" >&2; exit 1; }

OS=$(uname)
#OS=$(uname -o)
ARCH=$(uname -m)

VERSION=v0.32.4
#URL=https://github.com/derailed/k9s/releases/download/v0.32.4/k9s_Linux_arm64.tar.gz
#URL=https://github.com/derailed/k9s/releases/download/$VERSION/k9s_Linux_arm64.tar.gz
#
#case $OS in
    #Darwin) 
#esac

case $ARCH in
    # multipass on Mac-M1:
    arm64|aarch64) echo "CPU Architecture: Arm64";
          URL=https://github.com/derailed/k9s/releases/download/$VERSION/k9s_${OS}_arm64.tar.gz
          ;;
     x86_64) echo "CPU Architecture: Amd64";
          URL=https://github.com/derailed/k9s/releases/download/$VERSION/k9s_${OS}_amd64.tar.gz
          ;;

    *) die "Not implemented for architecture '$ARCH'";;
esac

set -x
FILE=${URL##*/}
echo FILE=$FILE

#exit

[ ! -f $FILE ] && {
    echo $URL
    echo https://github.com/derailed/k9s/releases/download/v0.32.4/k9s_Darwin_arm64.tar.gz
    #exit
    #wget -q $URL
    set -x; wget $URL; set +x
}

case $OS in
    Darwin) BIN=~/usr/bin/mac_os;;
    *)      BIN=~/bin;;
esac

mkdir -p $BIN/
tar xf $FILE k9s; mv k9s $BIN/

