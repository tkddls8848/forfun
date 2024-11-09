#!/usr/bin/bash

# time config
sudo timedatectl set-timezone Asia/Seoul
time=$(date "+%Y%m%d.%H%M%S")

# swapoff -a to disable swapping 
sudo swapoff -a
sudo sed -e '/swap/s/^/#/' -i /etc/fstab