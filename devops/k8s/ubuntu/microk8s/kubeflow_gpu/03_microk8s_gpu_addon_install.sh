#!/usr/bin/bash
# MicroK8s and GPU Addon Installation Script for Kubeflow GPU
# Ubuntu OS에서 MicroK8s 및 GPU 애드온 설치

set -e  # 오류 발생 시 스크립트 중단

## Check and fix snap service
echo "🔍 Snap 서비스 상태 확인 중..."
if ! systemctl is-active --quiet snapd; then
    echo "⚠️  Snap 서비스가 비활성화되어 있습니다. 활성화 중..."
    sudo systemctl enable snapd
    sudo systemctl start snapd
fi

## Clean up existing microk8s installation
echo "🧹 기존 MicroK8s 설치 정리 중..."
sudo snap remove microk8s --purge 2>/dev/null || true
sudo rm -rf /var/snap/microk8s 2>/dev/null || true
sudo rm -rf ~/.kube 2>/dev/null || true

## swapoff -a to disable swapping
sudo swapoff -a
sudo sed -e '/swap/s/^/#/' -i /etc/fstab

## install microk8s with error handling
echo "📦 MicroK8s 설치 중..."
if ! sudo snap install microk8s --classic --channel=1.32/stable; then
    echo "❌ MicroK8s 설치 실패"
    echo "다음 명령으로 상세 오류를 확인하세요:"
    echo "  sudo snap install microk8s --classic --channel=1.32/stable --verbose"
    exit 1
fi

## add user group for use microk8s
mkdir -p ~/.kube
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube

## Start MicroK8s
echo "🚀 MicroK8s 시작 중..."
sudo microk8s start

## Verify MicroK8s is ready
echo "🔍 MicroK8s 상태 확인 중..."
if ! sudo microk8s kubectl get nodes > /dev/null 2>&1; then
    echo "⚠️  MicroK8s API 서버가 아직 준비되지 않았습니다. 추가 대기 중..."
    sleep 60
    sudo microk8s status --wait-ready
fi

## install addons
echo "📦 기본 애드온 설치 중..."
sudo microk8s enable dns
sudo microk8s enable hostpath-storage
sudo microk8s enable rbac

echo "📦 MetalLB 애드온 설치 중..."

# 현재 네트워크 환경에 맞는 대역대 선택
# 시스템: 172.30.1.44/24, Docker: 172.17.0.1/16
# MetalLB: 172.30.1.240-172.30.1.250 (같은 네트워크 대역 사용)
sudo microk8s enable metallb:172.30.1.240-172.30.1.250

# MetalLB webhook 오류는 일반적이므로 대기
echo "⏳ MetalLB 초기화 대기 중..."
sleep 30

## install GPU addon
echo "🚀 MicroK8s GPU 애드온 설치 중..."
if ! sudo microk8s enable nvidia; then
    echo "⚠️  GPU 애드온 설치 실패. 재시도 중..."
    sleep 30
    sudo microk8s enable nvidia --validate=false
fi

## Wait for GPU addon to be ready
echo "⏳ GPU 애드온 초기화 대기 중... (최대 15분)"
TIMEOUT=900
COUNTER=0

# GPU Operator가 설치되어 있는지 확인
if sudo microk8s kubectl get namespace gpu-operator-resources > /dev/null 2>&1; then
    echo "🔍 GPU Operator 감지됨 - nvidia-operator-validator 파드 상태 확인 중..."
    
    while [ $COUNTER -lt $TIMEOUT ]; do
        if sudo microk8s kubectl get pods -n gpu-operator-resources -l app=nvidia-operator-validator --no-headers 2>/dev/null | grep -q "Running"; then
            echo "✅ GPU Operator 초기화 완료"
            break
        fi
        echo "대기 중... ($COUNTER/$TIMEOUT)"
        echo "현재 GPU Operator 파드 상태:"
        sudo microk8s kubectl get pods -n gpu-operator-resources -l app=nvidia-operator-validator 2>/dev/null || true
        sleep 5
        COUNTER=$((COUNTER + 5))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "⚠️  GPU Operator 초기화 타임아웃. 상태를 확인하세요:"
        sudo microk8s kubectl get pods -n gpu-operator-resources
        exit 1
    fi
else
    echo "🔍 MicroK8s GPU 애드온 감지됨 - NVIDIA Device Plugin 파드 상태 확인 중..."
    
    while [ $COUNTER -lt $TIMEOUT ]; do
        if sudo microk8s kubectl get pods -n kube-system -l app=nvidia-device-plugin-daemonset --no-headers 2>/dev/null | grep -q "Running"; then
            echo "✅ GPU 애드온 초기화 완료"
            break
        fi
        echo "대기 중... ($COUNTER/$TIMEOUT)"
        sleep 5
        COUNTER=$((COUNTER + 5))
    done
    
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "⚠️  GPU 애드온 초기화 타임아웃. 상태를 확인하세요:"
        sudo microk8s kubectl get pods -n kube-system -l app=nvidia-device-plugin-daemonset
        exit 1
    fi
fi

## Verify GPU installation
echo "🔍 GPU 설치 검증 중..."

# GPU Operator가 설치되어 있는지 확인
if sudo microk8s kubectl get namespace gpu-operator-resources > /dev/null 2>&1; then
    echo "=== GPU Operator 검증 ==="
    echo "GPU Operator 파드 상태:"
    sudo microk8s kubectl get pods -n gpu-operator-resources
    
    echo ""
    echo "GPU Operator 검증 로그:"
    sudo microk8s kubectl logs -n gpu-operator-resources -l app=nvidia-operator-validator -c nvidia-operator-validator --tail=20 2>/dev/null || echo "검증 로그를 가져올 수 없습니다."
else
    echo "=== MicroK8s GPU 애드온 검증 ==="
    echo "GPU 디바이스 플러그인 상태:"
    sudo microk8s kubectl get pods -n kube-system -l app=nvidia-device-plugin-daemonset
fi

echo ""
echo "GPU 노드 확인:"
sudo microk8s kubectl get nodes -o json | jq '.items[].status.allocatable | select(."nvidia.com/gpu" != null)' 2>/dev/null || {
    echo "GPU 노드 정보 확인:"
    sudo microk8s kubectl describe nodes | grep -i nvidia
}

## session restart
newgrp microk8s ### restart session for sudo microk8s

echo "✅ MicroK8s 및 GPU 애드온 설치 완료"