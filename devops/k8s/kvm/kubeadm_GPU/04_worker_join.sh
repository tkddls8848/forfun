#!/usr/bin/bash
# 04_worker_join.sh
# worker 노드를 k8s 클러스터에 join
# worker 노드에서 실행 (02_node_setup.sh + 재부팅 후 실행)
#
# 사용법 1 (자동, 권장):
#   bash 04_worker_join.sh
#   → ubuntu@k8s-master (DNS) 로 SSH 접속해 토큰을 자동 발급받아 join
#
# 사용법 2 (인수):
#   bash 04_worker_join.sh "kubeadm join <ip>:6443 --token xxx --discovery-token-ca-cert-hash sha256:xxx"
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
MASTER="ubuntu@k8s-master"

if [[ -n "$1" ]]; then
  log "join 실행 중 (인수 방식)..."
  sudo $1

else
  log "SSH로 $MASTER 에서 join 명령 자동 발급 중..."

  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    "$MASTER" "command -v kubeadm > /dev/null" \
    || error_exit "master($MASTER) SSH 접속 실패. SSH 키 설정을 확인하세요."

  JOIN_CMD=$(ssh -o StrictHostKeyChecking=no "$MASTER" \
    "sudo kubeadm token create --print-join-command 2>/dev/null")

  [[ -z "$JOIN_CMD" ]] && error_exit "master에서 join 명령 발급 실패."
  log "join 명령 수신 완료 → 실행 중..."
  sudo $JOIN_CMD
fi

# ────────────────────────────────────────────
# 완료
# ────────────────────────────────────────────
log "=== Phase 3 완료 ==="
echo ""
echo "✅ Worker join 완료"
echo "   master 노드에서 확인: kubectl get nodes"
