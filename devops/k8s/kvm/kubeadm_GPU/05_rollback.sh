#!/usr/bin/bash
# 05_rollback.sh
# kubeadm 클러스터 초기화 (NVIDIA 드라이버/toolkit/containerd/kubeadm 바이너리는 유지)
# 02_master_init.sh 부터 재실행하면 재구성 가능

set -e

log()  { echo "[$(date '+%H:%M:%S')] $1"; }
warn() { echo "⚠️  WARNING: $1"; }

log "=== Rollback: kubeadm 클러스터 초기화 ==="
echo ""
echo "🗑️  제거 대상:"
echo "   - kubeadm 클러스터 (kubeadm reset)"
echo "   - CNI 설정 (/etc/cni/, /var/lib/cni/)"
echo "   - iptables 규칙"
echo "   - kubectl 설정 (~/.kube/config)"
echo "   - ~/k8s-setup/ 작업 파일"
echo ""
echo "✅ 보존 대상:"
echo "   - NVIDIA 드라이버 (nvidia-smi 동작)"
echo "   - nvidia-container-toolkit"
echo "   - containerd (NVIDIA runtime 설정 포함)"
echo "   - kubeadm/kubelet/kubectl 바이너리"
echo ""
read -rp "계속 진행하시겠습니까? (y/N): " resp
[[ "$resp" =~ ^[yY]$ ]] || { echo "취소됨."; exit 0; }

# ────────────────────────────────────────────
# 1. kubeadm reset
# ────────────────────────────────────────────
log "1. kubeadm reset 실행 중..."
sudo kubeadm reset --force \
  --cri-socket=unix:///run/containerd/containerd.sock \
  2>/dev/null || warn "kubeadm reset 실패 (이미 초기화 상태일 수 있음)"

# ────────────────────────────────────────────
# 2. CNI 설정 제거
# ────────────────────────────────────────────
log "2. CNI 설정 제거 중..."
sudo rm -rf /etc/cni/net.d 2>/dev/null || true
sudo rm -rf /var/lib/cni 2>/dev/null || true

# ────────────────────────────────────────────
# 3. iptables 규칙 초기화
# ────────────────────────────────────────────
log "3. iptables 규칙 초기화..."
sudo iptables -F 2>/dev/null || true
sudo iptables -X 2>/dev/null || true
sudo iptables -t nat -F 2>/dev/null || true
sudo iptables -t nat -X 2>/dev/null || true

# ────────────────────────────────────────────
# 4. kubectl 설정 제거
# ────────────────────────────────────────────
log "4. kubectl 설정 제거 중..."
rm -f "$HOME/.kube/config" 2>/dev/null || true
rmdir "$HOME/.kube" 2>/dev/null || true  # 다른 config 있으면 보존

# ────────────────────────────────────────────
# 5. 작업 파일 정리
# ────────────────────────────────────────────
log "5. 작업 파일 정리 중..."
rm -rf "$HOME/k8s-setup" 2>/dev/null || true

# ────────────────────────────────────────────
# 6. 서비스 재시작 (containerd는 NVIDIA runtime 유지)
# ────────────────────────────────────────────
log "6. containerd 재시작..."
sudo systemctl restart containerd

# ────────────────────────────────────────────
# 상태 확인
# ────────────────────────────────────────────
log "=== Rollback 완료 - 상태 확인 ==="
echo ""
echo "✅ NVIDIA 드라이버:"
nvidia-smi | grep -E "Driver Version|GPU Name" || warn "nvidia-smi 실패"

echo ""
echo "✅ containerd 상태:"
systemctl is-active containerd \
  && echo "   containerd: 정상 (NVIDIA runtime 포함)" \
  || warn "containerd 비정상"

echo ""
echo "📋 재구성 순서:"
echo "   master 노드 → bash 02_master_init.sh"
echo "   worker 노드 → bash 03_worker_join.sh  (master join 명령 필요)"
echo "   GPU plugin  → bash 04_gpu_plugin.sh   (master 노드)"
