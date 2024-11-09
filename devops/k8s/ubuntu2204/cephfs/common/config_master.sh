#!/usr/bin/bash

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
sudo bash -c 'cat << EOF > /etc/resolv.conf
nameserver 8.8.8.8 #Google DNS
EOF'

# ssh password Authentication no to yes
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config_$time.backup
sudo sed -i -e 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo systemctl daemon-reload && sudo systemctl restart ssh

# root without password
sudo echo "vagrant ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers