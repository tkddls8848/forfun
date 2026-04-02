#!/bin/bash
set -e

# swap off
swapoff -a
sed -i '/swap/d' /etc/fstab

# 커널 고정
apt-mark hold linux-image-* linux-headers-* 2>/dev/null || true

# 공통 패키지
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y curl ca-certificates gnupg

# 커널 모듈
modprobe overlay br_netfilter
cat > /etc/modules-load.d/k3s.conf <<EOF
overlay
br_netfilter
EOF

# sysctl
cat > /etc/sysctl.d/99-k3s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system
