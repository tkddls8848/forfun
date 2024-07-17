#!/usr/bin/bash

sudo apt-get update -y
sudo timedatectl set-timezone Asia/Seoul

## config nfs directory system
sudo apt-get install nfs-kernel-server -y

# enroll directory for nfs server
sudo mkdir /mnt/share
sudo mkdir /mnt/share/prometheus-server
sudo mkdir /mnt/share/prometheus-alertmanager
sudo mkdir /srv/nfs-volume
sudo chown -R nobody:nogroup /mnt/share
sudo chown -R nobody:nogroup /srv/nfs-volume
sudo bash -c 'echo "/mnt/share  192.168.55.10/24(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports'
sudo bash -c 'echo "/mnt/share/prometheus-server  192.168.55.10/24(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports'
sudo bash -c 'echo "/mnt/share/prometheus-alertmanager  192.168.55.10/24(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports'
sudo bash -c 'echo "/srv/nfs-volume *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports'

# restart nfs
sudo exportfs -a
sudo systemctl restart nfs-kernel-server.service
