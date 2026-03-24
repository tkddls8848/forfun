#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# ── 1. Swap 비활성화 ──
swapoff -a
sed -i '/swap/d' /etc/fstab

# ── 2. sysctl (모듈 로드 불필요, 즉시 적용) ──
cat <<EOF > /etc/sysctl.d/99-k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# ── 3. 패키지 설치 ──
apt-get update -y
apt-get install -y \
  curl wget git vim jq \
  apt-transport-https ca-certificates gnupg \
  nfs-common open-iscsi \
  python3 python3-pip \
  net-tools iputils-ping \
  conntrack ethtool socat

# ── 4. containerd ──
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable containerd

# ── 5. 커널 모듈 등록 (패키지 설치 후 작성 → 리부트 시 새 커널 기준으로 로드) ──
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
nf_tables
nft_masq
EOF

# ── 6. 리부트 (커널 업데이트 적용 + modules-load.d 새 커널 기준 로드) ──
reboot
