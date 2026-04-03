#!/bin/bash
set -e

# swap off
swapoff -a
sed -i '/swap/d' /etc/fstab

# ── 커널 6.8 고정 (BeeGFS 7.4.6 클라이언트 모듈 호환 범위) ──────────
# Ubuntu 24.04 기본 AMI가 6.9+ 커널로 부팅될 수 있으므로
# 6.8 aws 커널을 명시적으로 설치하고 나머지를 고정합니다.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

KERN_PKG=$(apt-cache search 'linux-image-6\.8\.[0-9].*-aws$' \
  | sort -V | tail -1 | awk '{print $1}')
HDR_PKG="${KERN_PKG/linux-image/linux-headers}"

if [ -z "$KERN_PKG" ]; then
  echo "❌ linux-image-6.8.*-aws 패키지를 찾을 수 없습니다"
  exit 1
fi

echo "커널 설치: $KERN_PKG"
apt-get install -y "$KERN_PKG" "$HDR_PKG"

# 6.8 커널을 기본 부팅으로 설정
KERN_VER="${KERN_PKG#linux-image-}"
sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux ${KERN_VER}\"|" \
  /etc/default/grub
update-grub

# 6.8 이외의 커널 업그레이드 차단
apt-mark hold linux-image-* linux-headers-* 2>/dev/null || true
apt-mark unhold "$KERN_PKG" "$HDR_PKG" 2>/dev/null || true

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
