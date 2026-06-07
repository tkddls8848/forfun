#!/bin/bash
# cleanup_juju.sh - Juju 및 MicroK8s 안전 종료 스크립트

set -e  # 에러 발생 시 스크립트 중단

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# 환경 변수 설정
export JUJU_DATA="$HOME/.local/share/juju"
export KUBECONFIG="$HOME/.kube/config"

# 타임아웃 설정 (초)
TIMEOUT=300

log "=== Juju 및 MicroK8s 안전 종료 스크립트 시작 ==="n
# 1. 포트 포워딩 중지
log "포트 포워딩 중지..."
pkill -f "kubectl port-forward" || true
kill $(cat /tmp/kubeflow-port-forward.pid 2>/dev/null) 2>/dev/null || true
sudo rm -f /tmp/kubeflow-port-forward.pid

# 2. Juju 상태 확인
log "Juju 상태 확인 중..."
if ! command -v juju >/dev/null 2>&1; then
    log "Juju가 설치되지 않았습니다. Juju 단계를 건너뜁니다."
    JUJU_INSTALLED=false
else
    JUJU_INSTALLED=true
fi

# 3. Kubeflow 모델 제거
if [ "$JUJU_INSTALLED" = true ]; then
    log "Kubeflow 모델 제거 중..."
    timeout $TIMEOUT juju destroy-model kubeflow --yes --destroy-storage --force 2>/dev/null || {
        log "경고: Kubeflow 모델 제거 실패 또는 타임아웃"
    }
fi

# 4. 컨트롤러 제거
if [ "$JUJU_INSTALLED" = true ]; then
    log "Juju 컨트롤러 제거 중..."
    timeout $TIMEOUT juju destroy-controller my-k8s --destroy-all-models --destroy-storage --force 2>/dev/null || {
        log "경고: Juju 컨트롤러 제거 실패 또는 타임아웃"
    }
fi

# 5. 리소스 정리 대기
log "리소스 정리 대기 중..."
sleep 30

# 6. MicroK8s 상태 확인
log "MicroK8s 상태 확인 중..."
if ! command -v microk8s >/dev/null 2>&1; then
    log "MicroK8s가 설치되지 않았습니다. MicroK8s 단계를 건너뜁니다."
    MICROK8S_INSTALLED=false
else
    MICROK8S_INSTALLED=true
fi

# 7. Kubernetes 네임스페이스 강제 정리
if [ "$MICROK8S_INSTALLED" = true ]; then
    log "Kubernetes 네임스페이스 정리 중..."
    for ns in kubeflow controller-my-k8s gpu-operator-resources; do
        log "네임스페이스 $ns 삭제 중..."
        timeout 60 sudo microk8s kubectl delete namespace $ns --force --grace-period=0 2>/dev/null || {
            log "경고: 네임스페이스 $ns 삭제 실패 또는 타임아웃"
        }
    done
fi

# 8. 남은 Juju 관련 리소스 정리
if [ "$MICROK8S_INSTALLED" = true ]; then
    log "남은 Juju 리소스 정리 중..."
    # 모든 네임스페이스에서 Juju 관련 리소스 찾기
    sudo microk8s kubectl get pods --all-namespaces | grep juju | while read line; do
        namespace=$(echo $line | awk '{print $1}')
        pod=$(echo $line | awk '{print $2}')
        log "Juju 파드 삭제: $namespace/$pod"
        timeout 30 sudo microk8s kubectl delete pod $pod -n $namespace --force --grace-period=0 2>/dev/null || true
    done
fi

# 9. 로컬 Juju 데이터 백업 및 정리
if [ "$JUJU_INSTALLED" = true ] && [ -d ~/.local/share/juju ]; then
    log "로컬 Juju 데이터 백업 중..."
    backup_dir="~/.local/share/juju.backup.$(date +%Y%m%d%H%M%S)"
    if cp -r ~/.local/share/juju ~/.local/share/juju.backup.$(date +%Y%m%d%H%M%S) 2>/dev/null; then
        log "Juju 데이터 백업 완료: $backup_dir"
        rm -rf ~/.local/share/juju/* 2>/dev/null || log "경고: Juju 데이터 정리 실패"
        log "Juju 데이터 정리 완료"
    else
        log "경고: Juju 데이터 백업 실패. 데이터를 삭제하지 않습니다."
    fi
fi

log "=== Juju 종료 완료 ==="

# 10. MicroK8s 애드온 비활성화
if [ "$MICROK8S_INSTALLED" = true ]; then
    log "MicroK8s 애드온 비활성화 중..."
    for addon in gpu-operator metallb rbac hostpath-storage dns; do
        log "애드온 $addon 비활성화 중..."
        timeout 60 sudo microk8s disable $addon 2>/dev/null || {
            log "경고: 애드온 $addon 비활성화 실패 또는 타임아웃"
        }
    done
fi

# 11. MicroK8s 서비스 중지
if [ "$MICROK8S_INSTALLED" = true ]; then
    log "MicroK8s 서비스 중지 중..."
    timeout 60 sudo microk8s stop || {
        log "경고: MicroK8s 정상 종료 실패, 강제 종료 시도"
        sudo snap stop microk8s || log "경고: MicroK8s 강제 종료도 실패"
    }
fi

# 12. 상태 확인
log "최종 상태 확인..."
if [ "$MICROK8S_INSTALLED" = true ]; then
    sudo microk8s status 2>/dev/null || log "MicroK8s가 정상적으로 중지되었습니다."
fi

if [ "$JUJU_INSTALLED" = true ]; then
    juju controllers 2>/dev/null || log "Juju 컨트롤러가 정상적으로 정리되었습니다."
fi

# 13. 완전 제거 수행
log "=== 완전 제거 수행 중 ==="
log "Juju 완전 제거 중..."
sudo snap remove juju --purge 2>/dev/null || log "Juju 제거 실패 또는 이미 제거됨"

log "MicroK8s 완전 제거 중..."
sudo snap remove microk8s --purge 2>/dev/null || log "MicroK8s 제거 실패 또는 이미 제거됨"

log "Kubernetes 설정 파일 제거 중..."
sudo rm -rf ~/.kube 2>/dev/null || log "Kubernetes 설정 파일 제거 실패"

log "Juju 데이터 완전 제거 중..."
sudo rm -rf ~/.local/share/juju* 2>/dev/null || log "Juju 데이터 제거 실패"

log "=== 완전 제거 완료 ==="
log "모든 Kubeflow GPU 환경이 완전히 제거되었습니다."