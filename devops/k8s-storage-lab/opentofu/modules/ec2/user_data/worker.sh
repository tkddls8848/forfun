#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# ── k8s prerequisites ──
swapoff -a
sed -i '/swap/d' /etc/fstab

cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<EOF > /etc/sysctl.d/99-k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

apt-get update -y
apt-get install -y \
  curl wget git vim jq \
  apt-transport-https ca-certificates gnupg \
  nfs-common open-iscsi \
  python3 python3-pip \
  net-tools iputils-ping \
  lvm2 \
  chrony

systemctl enable --now chrony

# ── containerd (rook-ceph OSD도 containerd 사용) ──
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

echo "HCI worker node bootstrap complete"
