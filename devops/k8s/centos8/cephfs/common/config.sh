#!/usr/bin/env bash
set -euo pipefail

sudo timedatectl set-timezone Asia/Seoul

sudo swapoff -a
sudo sed -e '/swap/s/^/#/' -i /etc/fstab

sudo setenforce 0 2>/dev/null || true
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux

sudo systemctl stop firewalld 2>/dev/null || true
sudo systemctl disable firewalld 2>/dev/null || true
sudo systemctl stop NetworkManager 2>/dev/null || true
sudo systemctl disable NetworkManager 2>/dev/null || true

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf >/dev/null
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo modprobe br_netfilter
sudo sysctl --system

sudo dnf install -y iproute-tc

cat <<EOF | sudo tee /etc/resolv.conf >/dev/null
nameserver 8.8.8.8
EOF

echo "Base node configuration complete"
