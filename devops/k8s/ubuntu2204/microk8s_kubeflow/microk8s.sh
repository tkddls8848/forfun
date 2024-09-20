#!/usr/bin/bash

# swapoff -a to disable swapping
sudo swapoff -a
sudo sed -e '/swap/s/^/#/' -i /etc/fstab

## expand logical volume and ext4 filesystem to 100% phsical disk
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv

## install microk8s
sudo snap install microk8s --channel=1.29-strict/stable

## add user group for use microk8s
mkdir -p ~/.kube
sudo usermod -a -G snap_microk8s $USER
sudo chown -f -R $USER ~/.kube
