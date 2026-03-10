#!/usr/bin/bash
# 03_master_init.sh
# master 노드 초기화 + CNI 설치
# master 노드에서만 실행
#
# 사용법:
#   bash 03_master_init.sh               # 단일 노드 모드 (기본값, master untaint 포함)
#   SINGLE_NODE=false bash 03_master_init.sh  # 멀티 노드 모드 (untaint 생략)

set -e

SINGLE_NODE=${SINGLE_NODE:-false}      # false: 멀티 노드 (worker 있음, master taint 유지)
POD_CIDR="10.244.0.0/16"              # Flannel 기본값
K8S_SETUP_DIR="$HOME/k8s-setup"

log()        { echo "[$(date '+%H:%M:%S')] $1"; }
error_exit() { echo "❌ ERROR: $1"; exit 1; }

log "=== Phase 3: Master 초기화 시작 ==="
log "   단일 노드 모드: $SINGLE_NODE"

# ────────────────────────────────────────────
# 사전 확인
# ────────────────────────────────────────────
kubeadm version > /dev/null 2>&1 \
  || error_exit "kubeadm 없음. 02_node_setup.sh 실행 후 재부팅 하세요."
systemctl is-active --quiet containerd \
  || error_exit "containerd 비정상. 'systemctl status containerd' 확인하세요."

# ────────────────────────────────────────────
# 1. kubeadm init
# ────────────────────────────────────────────
log "1. kubeadm init 실행 중..."
sudo kubeadm init \
  --pod-network-cidr="$POD_CIDR" \
  --cri-socket=unix:///run/containerd/containerd.sock \
  | tee /tmp/kubeadm_init.log

# ────────────────────────────────────────────
# 2. kubectl 설정
# ────────────────────────────────────────────
log "2. kubectl 설정 중..."
mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# ────────────────────────────────────────────
# 3. Flannel CNI 설치
# ────────────────────────────────────────────
log "3. Flannel CNI 설치 중..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# ────────────────────────────────────────────
# 4. 단일 노드 모드: master taint 제거
#    kubeadm init 후 master에는 기본으로 taint가 걸려
#    일반 Pod가 스케줄되지 않는다.
#    단일 노드에서는 이 taint를 제거해 GPU Pod 포함
#    모든 워크로드가 master에서 실행되도록 허용한다.
# ────────────────────────────────────────────
if [[ "$SINGLE_NODE" == "true" ]]; then
  log "4. [단일 노드] master taint 제거 중..."
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- \
    2>/dev/null || true
  log "   완료: 이 노드에서 모든 Pod 스케줄 허용됨"
else
  log "4. [멀티 노드] taint 유지 (worker join 후 GPU Pod는 worker에서 실행)"
fi

# ────────────────────────────────────────────
# 5. worker join 명령 저장
# ────────────────────────────────────────────
log "5. worker join 명령 저장 중..."
mkdir -p "$K8S_SETUP_DIR"
kubeadm token create --print-join-command \
  | tee "$K8S_SETUP_DIR/worker_join.sh"
chmod +x "$K8S_SETUP_DIR/worker_join.sh"
log "   저장 위치: $K8S_SETUP_DIR/worker_join.sh"

# ────────────────────────────────────────────
# 6. Master 노드 Ready 대기
# ────────────────────────────────────────────
log "6. Master 노드 Ready 대기 중 (최대 3분)..."
for i in $(seq 1 36); do
  STATUS=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | head -1)
  echo "  [$i/36] 노드 상태: ${STATUS:-Initializing}"
  [[ "$STATUS" == "Ready" ]] && echo "✅ Master Ready" && break
  sleep 5
done

# ────────────────────────────────────────────
# 완료
# ────────────────────────────────────────────
log "=== Master 초기화 완료 ==="
echo ""
kubectl get nodes -o wide
echo ""
echo "Worker join 명령:"
cat "$K8S_SETUP_DIR/worker_join.sh"
echo ""
echo "다음 단계:"
if [[ "$SINGLE_NODE" == "true" ]]; then
  echo "  단일 노드 → bash 05_gpu_plugin.sh"
else
  echo "  각 Worker VM에서: bash ~/04_worker_join.sh"
  echo "  모든 worker join 후: bash 05_gpu_plugin.sh"
fi
