#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# cephadm 의존성
apt-get update -qq
apt-get install -y python3 podman nvme-cli lvm2 xfsprogs

# cephadm 설치
apt-get install -y cephadm

# BeeGFS 7.4.6 저장소
wget -q https://www.beegfs.io/release/beegfs_7.4.6/gpg/GPG-KEY-beegfs \
  -O- | gpg --dearmor > /etc/apt/trusted.gpg.d/beegfs.gpg
echo "deb https://www.beegfs.io/release/beegfs_7.4.6/ noble non-free" \
  > /etc/apt/sources.list.d/beegfs.list
apt-get update -qq

# BeeGFS 서버 패키지 (클라이언트 제외 — frontend EC2에서만 필요)
apt-get install -y \
  beegfs-mgmtd \
  beegfs-meta \
  beegfs-storage \
  beegfs-utils

echo "backend AMI 패키지 설치 완료"
