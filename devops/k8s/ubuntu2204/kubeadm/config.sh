#!/usr/bin/bash

sudo apt-get install ntp -y
sudo systemctl start ntp
sudo systemctl enable ntp

# swapoff -a to disable swapping
sudo swapoff -a
sudo sed -e '/swap/s/^/#/' -i /etc/fstab

# set SELinux disable
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
sestatus

# enabling iptables kernel options
cat << EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF
 
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl --system

# disable firewall
sudo ufw disable

# config DNS
sudo bash -c 'cat << EOF >> /etc/hosts
192.168.70.10  k8s-master
192.168.70.21  k8s-worker1
192.168.70.22  k8s-worker2
192.168.70.23  k8s-worker3
192.168.70.100  k8s-nfs
EOF'

# config DNS
sudo bash -c 'cat << EOF > /etc/resolv.conf
nameserver 8.8.8.8 #Google DNS
EOF'

# ssh password Authentication no to yes
sudo sed -i.bak -e 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo systemctl daemon-reload && sudo systemctl restart ssh

# root without password
sudo echo "vagrant ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

