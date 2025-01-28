#!/usr/bin/bash

sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils

## usergroup config(libvirt, kvm)
sudo adduser `id -un` libvirt
sudo adduser `id -un` kvm

sudo systemctl enable libvirtd
sudo systemctl start libvirtd
sudo usermod -aG libvirt $(whoami)
newgrp libvirt

## load kvm module
sudo modprobe kvm

## reboot
sudo reboot