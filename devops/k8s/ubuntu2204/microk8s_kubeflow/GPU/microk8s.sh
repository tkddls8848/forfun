#!/usr/bin/bash

# swapoff -a to disable swapping
sudo swapoff -a
sudo sed -e '/swap/s/^/#/' -i /etc/fstab

## expand logical volume and ext4 filesystem to 100% phsical disk
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv

### enable nvidia GPU
#sudo apt install build-essential dkms ubuntu-drivers-common -y
#sudo add-apt-repository ppa:graphics-drivers/ppa -y
#sudo apt-get update
#sudo ubuntu-drivers autoinstall
##ubuntu-drivers devices
#sudo apt install nvidia-driver-560 -y
#sudo reboot
#nvidia-smi ##verify install

## install microk8s
sudo snap install microk8s --classic --channel=1.29/stable

## add user group for use microk8s
mkdir -p ~/.kube
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube
newgrp microk8s ## restart session required

## install addons
#microk8s status --wait-ready
sudo microk8s enable dns hostpath-storage metallb:10.64.140.43-10.64.140.49 rbac
