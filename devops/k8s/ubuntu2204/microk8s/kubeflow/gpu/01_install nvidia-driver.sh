#!/usr/bin/bash
#run script in ubuntu OS

## blacklist nouveau
sudo tee /etc/modules-load.d/ipmi.conf <<< "ipmi_msghandler" \
    && sudo tee /etc/modprobe.d/blacklist-nouveau.conf <<< "blacklist nouveau" \
    && sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf <<< "options nouveau modeset=0"
sudo update-initramfs -u
sudo init 6

## remove installed old nvidia-driver
sudo apt-get --purge -y remove 'nvidia*'

## Installing nvidia driver
sudo ubuntu-drivers autoinstall