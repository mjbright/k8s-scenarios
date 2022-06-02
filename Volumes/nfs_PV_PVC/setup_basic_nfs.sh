#!/bin/bash

CP=k8scp
CP_IP=$( hostname -i )

WO=worker


MNT=/mnt/nfs-vol

die() { echo "$0: die - $*" >&2; exit 1; }

PRESS() {
    echo; echo $*
    echo "Press return>"
    read DUMMY
    [ "$DUMMY" = "q" ] && exit 0
    [ "$DUMMY" = "Q" ] && exit 0
}

grep -q " $WORKER" /etc/hosts || die "No $WORKER entry found in /etc/hosts"

case $(hostname) in
    k8scp) CP=k8scp;;
    cp) CP=cp;;

    *)     die "Unexpected node name $(hostname)"
esac

ssh="ssh -i  ~/.ssh/t-key.pem $WO"


PRESS "---- Configuring NFS on $CP node:"
dpkg -l | grep nfs-kernel-server || {
    echo; echo 'sudo apt-get update && sudo apt-get install -y nfs-kernel-server'
    sudo apt-get update && sudo apt-get install -y nfs-kernel-server
}

sudo mkdir -p $MNT
sudo chmod 1777 $MNT

[ ! -f $MNT/NFScreation.log ] && {
    echo; echo sudo tee $MNT/NFScreation.log
    #sudo bash -c 'echo $(date): NFS volume created from host $(hostname) > $MNT/NFScreation.log'
    bash -c "echo $(date): NFS volume created from host $(hostname)" | sudo tee $MNT/NFScreation.log
}

grep $MNT /etc/exports || {
    echo $MNT/ '*(rw,sync,no_root_squash,subtree_check)' | sudo tee -a /etc/exports 
    #cat /etc/exports 
    # Reload exports:
    sudo exportfs -ra
}

PRESS "---- Configuring NFS on $WO node:"
$ssh sudo dpkg -l | grep nfs-common || $ssh sudo apt-get -y install nfs-common
$ssh showmount -e $CP_IP
$ssh sudo mount $CP_IP:$MNT /mnt
$ssh ls -l /mnt

