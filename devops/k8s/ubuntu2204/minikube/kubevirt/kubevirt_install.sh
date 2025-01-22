#!/usr/bin/bash

## install kubevirt
sudo apt-get install qemu-system-x86 libvirt-daemon-system libvirt-clients bridge-utils -y
sudo systemctl status libvirtd
sudo systemctl restart libvirtd
sudo adduser `id -un` libvirt
sudo adduser `id -un` kvm
sudo modprobe kvm
sudo reboot

sudo dbus-uuidgen --ensure

## run minikube with kvm driver
minikube start --vm-driver kvm2 --cpus 4 --memory 8192
alias kubectl="minikube kubectl --"
#minikube start --addons=kubevirt ## KubeVirt Addon broken due to missing curl in Pod 