#!/bin/bash
# Worker: 커널 6.8 설치 + GRUB 설정 (재부팅 전 단계)
# BeeGFS 7.4.6은 커널 6.11까지만 지원 — 6.8로 다운그레이드 필요
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq

# 커널 6.8 패키지 탐색 및 설치
IMG=$(apt-cache search 'linux-image-6\.8.*-aws' | awk '{print $1}' | sort -V | tail -1)
HDR=$(apt-cache search 'linux-headers-6\.8.*-aws' | awk '{print $1}' | sort -V | tail -1)
[ -z "$IMG" ] && { echo "ERROR: linux-image-6.8.*-aws 패키지 없음"; exit 1; }
apt-get install -y "$IMG" "$HDR"

# 설치된 6.8 커널 버전 문자열
KERNEL_68=$(dpkg -l | grep 'linux-image-6\.8.*-aws' \
  | awk '{print $2}' | sed 's/linux-image-//' | sort -V | tail -1)
echo "설치된 6.8 커널: ${KERNEL_68}"

# GRUB 기본값을 6.8로 설정
sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux ${KERNEL_68}\"|" \
  /etc/default/grub
update-grub

# 현재 커널(6.12+)은 hold하여 자동 업그레이드 방지
CURRENT_KERNEL=$(uname -r)
apt-mark hold "linux-image-${CURRENT_KERNEL}" "linux-headers-${CURRENT_KERNEL}" 2>/dev/null || true

echo "커널 6.8 설치 완료 — 재부팅 후 BeeGFS 모듈 빌드 진행"
