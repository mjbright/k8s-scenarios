#!/bin/bash

CP=k8scp
WO=worker

echo; echo "---- Configuring NFS on $CP node:"
sudo apt-get update && sudo apt-get install -y nfs-kernel-server
sudo mkdir /opt/sfw
sudo chmod 1777 /opt/sfw/
sudo bash -c "echo $(date): NFS volume created from host $(hostname)"  > /opt/sfw/NFScreation.log'
grep sfw /etc/exports || echo '/opt/sfw/ *(rw,sync,no_root_squash,subtree_check)' | sudo tee -a /etc/exports 
grep sfw /etc/exports || echo '/opt/sfw/ *(rw,sync,no_root_squash,subtree_check)' | sudo tee -a /etc/exports 
cat /etc/exports 
exportfs -ra
sudo exportfs -ra

echo; echo "---- Configuring NFS on $WO node:"
ssh $WO sudo apt-get -y install nfs-common
ssh $WO showmount -e $CP
ssh $WO sudo mount $CP:/opt/sfw /mnt
ssh $WO ls -l /mnt

