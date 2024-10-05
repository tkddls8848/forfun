#!/usr/bin/bash
#run script in ubuntu OS

# swapoff -a to disable swapping
sudo swapoff -a
sudo sed -e '/swap/s/^/#/' -i /etc/fstab

## install microk8s
sudo snap install microk8s --classic --channel=1.30/stable

## add user group for use microk8s
mkdir -p ~/.kube
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube

## install addons
#microk8s status --wait-ready
sudo microk8s enable nvidia
sudo microk8s enable dns hostpath-storage metallb:10.64.140.43-10.64.140.49 rbac

## sesstion restart
newgrp microk8s ## restart session required
