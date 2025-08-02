#!/usr/bin/bash
# NVIDIA Driver Installation Script for Kubeflow GPU
# Ubuntu OS에서 NVIDIA 드라이버 설치

set -e  # 오류 발생 시 스크립트 중단

## blacklist nouveau
sudo tee /etc/modules-load.d/ipmi.conf <<< "ipmi_msghandler" \
    && sudo tee /etc/modprobe.d/blacklist-nouveau.conf <<< "blacklist nouveau" \
    && sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf <<< "options nouveau modeset=0"
sudo update-initramfs -u

## remove installed old nvidia-driver
sudo apt-get --purge -y remove 'nvidia*'

## Installing nvidia driver
sudo apt install ubuntu-drivers-common -y
sudo ubuntu-drivers autoinstall

echo "✅ NVIDIA 드라이버 설치 완료"
echo "⚠️  NVIDIA 드라이버 설치를 위해 시스템 재부팅이 필요합니다."
echo "재부팅을 진행하시겠습니까? (y/N)"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "시스템을 재부팅합니다..."
    sudo init 6
else
    echo "재부팅을 건너뜁니다. 수동으로 재부팅 후 다음 스크립트를 실행하세요."
    exit 0
fi