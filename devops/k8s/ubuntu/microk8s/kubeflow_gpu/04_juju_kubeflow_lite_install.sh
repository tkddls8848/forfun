#!/usr/bin/bash
# Juju and Kubeflow Lite Installation Script for Kubeflow GPU
# Ubuntu OS에서 Juju 및 Kubeflow Lite 설치

set -e  # 오류 발생 시 스크립트 중단

## install juju
sudo snap install juju --channel=3.6/stable
mkdir -p ~/.local/share

## Set environment variable
export JUJU_DATA="$HOME/.local/share/juju"

## Complete Juju cleanup and fresh start
echo "🧹 Juju 완전 정리 및 새로 시작..."

# 1. Juju snap 완전 제거
echo "1. Juju snap 완전 제거 중..."
sudo snap remove juju --purge 2>/dev/null || true

# 2. 모든 Juju 관련 데이터 완전 삭제
echo "2. 모든 Juju 데이터 완전 삭제 중..."
rm -rf ~/.local/share/juju 2>/dev/null || true
rm -rf ~/.juju 2>/dev/null || true
rm -rf ~/.config/juju 2>/dev/null || true
rm -rf ~/.cache/juju 2>/dev/null || true

# 3. Juju 재설치
echo "3. Juju 새로 설치 중..."
sudo snap install juju --channel=3.6/stable

# 4. Juju 환경 초기화
echo "4. Juju 환경 초기화 중..."
export JUJU_DATA="$HOME/.local/share/juju"
mkdir -p ~/.local/share/juju

# 5. Kubernetes 클러스터를 Juju에 추가
echo "5. Kubernetes 클러스터를 Juju에 추가 중..."
microk8s config | juju add-k8s my-k8s --client

## bootstraping juju and microk8s
echo "🚀 Juju 부트스트랩 중..."

# 새로 설치된 Juju이므로 바로 부트스트랩 수행
echo "부트스트랩 수행 중..."
juju bootstrap my-k8s

echo "📦 Kubeflow 모델 생성 중..."
juju add-model kubeflow

## install charmed kubeflow lite
echo "🔧 Charmed Kubeflow Lite 배포 중..."
juju deploy kubeflow-lite --trust --channel=1.10/stable

## Configure authentication for dashboard
echo "🔐 인증 설정 중..."
juju config dex-auth static-username=admin
juju config dex-auth static-password=admin

## config filesystem
echo "⚙️  파일시스템 설정 중..."
sudo sysctl fs.inotify.max_user_instances=1280
sudo sysctl fs.inotify.max_user_watches=655360

## Wait for Kubeflow to be ready
echo "⏳ Kubeflow 배포 완료 대기 중... (최대 30분)"
timeout 1800 bash -c 'until juju status kubeflow 2>/dev/null | grep -q "active"; do sleep 60; echo "대기 중..."; done' || {
    echo "⚠️  Kubeflow 배포 타임아웃. 상태를 확인하세요:"
    juju status
    exit 1
}

## Get the IP address of Istio ingress gateway load balancer
echo "🌐 포트 포워딩 설정 중..."
IP=$(microk8s kubectl -n kubeflow get svc istio-ingressgateway-workload -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

## port-forward Istio ingress gateway load balancer in background
nohup microk8s kubectl port-forward -n kubeflow svc/istio-ingressgateway-workload 1234:80 > /tmp/kubeflow-port-forward.log 2>&1 &
echo $! > /tmp/kubeflow-port-forward.pid

## Verify GPU is available for Kubeflow
echo "🔍 GPU 가용성 확인 중..."
if microk8s kubectl get nodes -o json | jq -e '.items[].status.allocatable | select(."nvidia.com/gpu" != null)' > /dev/null 2>&1; then
    echo "✅ GPU가 Kubeflow에서 사용 가능합니다"
    microk8s kubectl get nodes -o json | jq '.items[].status.allocatable | select(."nvidia.com/gpu" != null)'
else
    echo "⚠️  GPU가 감지되지 않았습니다. GPU 작업이 제한될 수 있습니다."
fi

echo "✅ Juju 및 Kubeflow 설치 완료"
echo "🌐 Kubeflow 대시보드: http://localhost:1234"
echo "👤 사용자명: admin"
echo "🔑 비밀번호: admin"
echo "📋 포트 포워딩 PID: $(cat /tmp/kubeflow-port-forward.pid)"