#!/usr/bin/bash

sudo apt-get update -y
sudo timedatectl set-timezone Asia/Seoul

## config nfs directory system
sudo apt-get install nfs-kernel-server -y

## enroll directory for nfs server
sudo mkdir /mnt/share
sudo chown -R nobody:nogroup /mnt/share
sudo bash -c 'echo "/mnt/share  192.168.56.10/24(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports'

## restart nfs
sudo exportfs -a
sudo systemctl restart nfs-kernel-server.service
