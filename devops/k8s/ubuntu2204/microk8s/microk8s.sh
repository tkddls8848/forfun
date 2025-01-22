#!/usr/bin/bash

## swapoff -a to disable swapping
sudo swapoff -a
sudo sed -e '/swap/s/^/#/' -i /etc/fstab

## expand logical volume and ext4 filesystem to 30GB phsical disk
sudo lvextend -L +30G /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv

### enable nvidia GPU
#sudo apt install build-essential dkms ubuntu-drivers-common -y
#sudo add-apt-repository ppa:graphics-drivers/ppa -y
#sudo apt-get update
#sudo ubuntu-drivers autoinstall
##ubuntu-drivers devices
#sudo apt install nvidia-driver-560 -y
#sudo reboot
#nvidia-smi #verify install

## install microk8s
#sudo snap install microk8s --channel=1.29-strict/stable # no nvidia gpu
sudo snap install microk8s --classic --channel=1.30/stable # nvidia gpu

## add user group for use microk8s
mkdir -p ~/.kube
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube

## install addons
#Sequential addon addition recommended
addons=(dns hostpath-storage metallb:10.64.140.43-10.64.140.60 rbac)
for addon in "${addons[@]}" 
do
    sudo microk8s enable $addon
done

## microk8s kubectl alias
echo 'alias kubectl=microk8s kubectl' >>~/.bashrc
