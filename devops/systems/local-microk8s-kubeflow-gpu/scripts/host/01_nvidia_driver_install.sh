#!/usr/bin/bash
# NVIDIA Driver Installation Script for Kubeflow GPU
# Ubuntu OS에서 NVIDIA 드라이버 설치
# 사용: bash 01_nvidia_driver_install.sh [--reboot]

set -e  # 오류 발생 시 스크립트 중단

## blacklist nouveau
sudo tee /etc/modules-load.d/ipmi.conf <<< "ipmi_msghandler"
sudo tee /etc/modprobe.d/blacklist-nouveau.conf <<< "blacklist nouveau"
sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf <<< "options nouveau modeset=0"
sudo update-initramfs -u

## 드라이버가 이미 정상 동작 중이면 재설치 스킵
# (일괄 'nvidia*' purge는 nvidia-container-toolkit까지 제거될 수 있어 위험)
if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
    echo "✅ NVIDIA 드라이버가 이미 동작 중입니다. 설치를 건너뜁니다."
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
    exit 0
fi

## 기존 드라이버 패키지가 설치되어 있을 때만 조건부 제거 (대상 패턴 축소)
if dpkg -l | grep -qE '^ii\s+nvidia-driver-'; then
    echo ">> 기존 NVIDIA 드라이버 제거 중..."
    sudo apt-get --purge -y remove 'nvidia-driver-*' 'libnvidia-*'
    sudo apt-get autoremove -y
fi

## Installing nvidia driver
sudo apt-get update
sudo apt-get install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall

echo "✅ NVIDIA 드라이버 설치 완료"
echo "⚠️  NVIDIA 드라이버 적용을 위해 시스템 재부팅이 필요합니다."

## 재부팅 처리: --reboot 플래그(자동화용) 또는 tty에서만 대화형 질문
if [[ "${1:-}" == "--reboot" ]]; then
    echo "시스템을 재부팅합니다..."
    sudo init 6
elif [[ -t 0 ]]; then
    read -rp "재부팅을 진행하시겠습니까? (y/N) " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "시스템을 재부팅합니다..."
        sudo init 6
    else
        echo "재부팅을 건너뜁니다. 수동으로 재부팅 후 다음 스크립트를 실행하세요."
    fi
else
    echo "재부팅을 건너뜁니다. 수동으로 재부팅 후 다음 스크립트를 실행하세요."
    echo "(자동 재부팅하려면 --reboot 플래그를 사용하세요.)"
fi