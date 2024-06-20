#!/usr/bin/bash

# time config
sudo timedatectl set-timezone Asia/Seoul

# allow ssh login with password
sudo time=$(date "+%Y%m%d.%H%M%S")

# swapoff -a to disable swapping
sudo swapoff -a
sudo sed -e '/swap/s/^/#/' -i /etc/fstab

# set SELinux disable
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
sestatus

# disable firewalld and NetworkManager
sudo systemctl stop firewalld && sudo systemctl disable firewalld
sudo systemctl stop NetworkManager && sudo systemctl disable NetworkManager

# enabling iptables kernel options
sudo bash -c 'cat << EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF'
sudo modprobe br_netfilter
sudo sysctl --system

# enable ip forward
sudo dnf install -y iproute-tc
sudo bash -c 'cat << EOF >> /etc/sysctl.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding=1
EOF' 
sudo sysctl -p

# config DNS
sudo bash -c 'cat << EOF > /etc/resolv.conf
nameserver 8.8.8.8 #Google DNS
EOF'

# ssh password Authentication no to yes
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config_$time.backup
sudo sed -i -e 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo systemctl restart sshd

# root without password
sudo su -
echo "vagrant ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers