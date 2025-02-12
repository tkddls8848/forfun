#!/usr/bin/bash

## install kubevirt
sudo dnf install -y qemu-kvm libvirt virt-install bridge-utils virt-manager
sudo systemctl enable --now libvirtd

## install kvm2 driver for minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/docker-machine-driver-kvm2
chmod +x docker-machine-driver-kvm2
sudo mv docker-machine-driver-kvm2 /usr/local/bin/

sudo usermod -aG libvirt $(whoami)
sudo usermod -aG kvm $(whoami)
newgrp libvirt
newgrp kvm
sudo chmod +x /usr/libexec/qemu-kvm

sudo reboot

sudo modprobe kvm_amd
sudo dbus-uuidgen --ensure

## run minikube with kvm driver
minikube start --vm-driver kvm2 --cpus 4 --memory 8192
alias kubectl="minikube kubectl --"
#minikube start --addons=kubevirt ## KubeVirt Addon broken due to missing curl in Pod 