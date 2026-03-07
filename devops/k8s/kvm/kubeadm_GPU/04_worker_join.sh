#!/usr/bin/bash
# 04_worker_join.sh
# worker 노드를 k8s 클러스터에 join
# worker 노드에서 실행 (02_node_setup.sh + 재부팅 후 실행)
#
# 사용법 1 (인수):
#   bash 04_worker_join.sh "kubeadm join <ip>:6443 --token xxx --discovery-token-ca-cert-hash sha256:xxx"
#
# 사용법 2 (환경변수):
#   MASTER_IP=192.168.1.10 TOKEN=xxx HASH=xxx bash 04_worker_join.sh
#
# master에서 join 명령 확인:
#   cat ~/k8s-setup/worker_join.sh

set -e

log()        { echo "[$(date '+%H:%M:%S')] $1"; }
error_exit() { echo "❌ ERROR: $1"; exit 1; }

log "=== Phase 3: Worker Join 시작 ==="

# ────────────────────────────────────────────
# 사전 확인
# ────────────────────────────────────────────
kubeadm version > /dev/null 2>&1 \
  || error_exit "kubeadm 없음. 02_node_setup.sh 실행 후 재부팅 하세요."
systemctl is-active --quiet containerd \
  || error_exit "containerd 비정상. 'systemctl status containerd' 확인하세요."

# ────────────────────────────────────────────
# 이전 kubeadm 흔적 제거 (재join 대비)
# ────────────────────────────────────────────
if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  log "이전 kubeadm 흔적 감지 → 자동 reset 중..."
  sudo kubeadm reset --force \
    --cri-socket=unix:///run/containerd/containerd.sock 2>/dev/null || true
  sudo rm -rf /etc/cni/net.d /var/lib/cni 2>/dev/null || true
  sudo systemctl restart containerd
  log "   reset 완료"
fi

# ────────────────────────────────────────────
# kubeadm join 실행
# ────────────────────────────────────────────
if [[ -n "$1" ]]; then
  log "join 실행 중 (인수 방식)..."
  sudo $1

elif [[ -n "$MASTER_IP" && -n "$TOKEN" && -n "$HASH" ]]; then
  log "join 실행 중 (master: $MASTER_IP)..."
  sudo kubeadm join "${MASTER_IP}:6443" \
    --token "$TOKEN" \
    --discovery-token-ca-cert-hash "sha256:${HASH}"

else
  error_exit "join 명령이 없습니다.

사용법 1: bash 04_worker_join.sh \"kubeadm join <ip>:6443 --token xxx --discovery-token-ca-cert-hash sha256:xxx\"
사용법 2: MASTER_IP=x.x.x.x TOKEN=xxx HASH=xxx bash 04_worker_join.sh

master에서 join 명령 확인:
  cat ~/k8s-setup/worker_join.sh"
fi

# ────────────────────────────────────────────
# 완료
# ────────────────────────────────────────────
log "=== Phase 3 완료 ==="
echo ""
echo "✅ Worker join 완료"
echo "   master 노드에서 확인: kubectl get nodes"
