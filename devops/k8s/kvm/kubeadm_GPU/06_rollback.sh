#!/usr/bin/bash
# 06_rollback.sh
# 단계별 선택 롤백
#
# 각 단계는 해당 단계 이후 변경사항을 모두 역순으로 제거합니다.
#   1단계 이전: VM 전체 삭제 (디스크 포함)
#   2단계 이전: VM 재생성 필요 (= 1단계 이전 수준)
#   3단계 이전: kubeadm reset, CNI/iptables 초기화, kubectl 설정 제거
#   4단계 이전: worker 노드 제거 후 3단계 이전 수행
#   5단계 이전: GPU Device Plugin 제거만 수행
#
# 실행: bash 06_rollback.sh

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
warn() { echo "[$(date '+%H:%M:%S')] WARNING: $*"; }

VM_NAMES=("k8s-master" "k8s-worker1" "k8s-worker2")
VM_DIR="/var/lib/libvirt/images"
SETUP_DIR="/var/lib/libvirt/images/k8s-setup"
VM_IPS_ENV="$SETUP_DIR/vm_ips.env"
SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -i $SSH_KEY"

# ────────────────────────────────────────────
# 메뉴
# ────────────────────────────────────────────
echo ""
echo "=== K8s 단계별 롤백 ==="
echo ""
echo "  단계 번호를 입력하면 해당 단계 실행 이전 상태로 되돌립니다."
echo "  (해당 단계 포함 이후 모든 단계가 역순으로 제거됩니다)"
echo ""
echo "  01 : VM 생성 이전     (VM 전체 삭제, cloud image / host_info.env 보존)"
echo "  02 : 노드 설정 이전   (VM 삭제 후 재생성 권장)"
echo "  03 : Master init 이전 (kubeadm reset, CNI/iptables 초기화, kubectl 설정 제거)"
echo "  04 : Worker join 이전 (Worker 노드 제거 + kubeadm reset)"
echo "  05 : GPU plugin 이전  (GPU Device Plugin / CUDA 테스트 Pod 제거)"
echo ""
read -rp "어느 단계 이전까지 롤백하시겠습니까? (01~05, q=취소): " CHOICE

# 앞의 0 제거하여 정규화 (01→1, 05→5)
CHOICE="${CHOICE#0}"

case "$CHOICE" in
  1|2|3|4|5) ;;
  q|Q) echo "취소됨."; exit 0 ;;
  *) echo "ERROR: 잘못된 입력입니다. (01~05 또는 q)"; exit 1 ;;
esac

echo ""
case "$CHOICE" in
  1) echo "  → 01단계(VM 생성) 이전으로 롤백: VM 전체 삭제" ;;
  2) echo "  → 02단계(노드 설정) 이전으로 롤백: VM 삭제 후 재생성 필요" ;;
  3) echo "  → 03단계(Master init) 이전으로 롤백: 클러스터 전체 해체" ;;
  4) echo "  → 04단계(Worker join) 이전으로 롤백: Worker 노드 제거" ;;
  5) echo "  → 05단계(GPU plugin) 이전으로 롤백: GPU Plugin 제거" ;;
esac
echo ""
read -rp "계속 진행하시겠습니까? (y/N): " resp
[[ "$resp" =~ ^[yY]$ ]] || { echo "취소됨."; exit 0; }
echo ""

# ────────────────────────────────────────────
# 롤백 함수
# ────────────────────────────────────────────

rollback_05() {
  log "--- [05단계 롤백] GPU Device Plugin 제거 ---"
  if kubectl get nodes &>/dev/null; then
    kubectl delete daemonset nvidia-device-plugin-daemonset \
      -n kube-system --ignore-not-found=true 2>/dev/null || true
    kubectl delete pod cuda-test --ignore-not-found=true 2>/dev/null || true
    log "   GPU Plugin / 테스트 Pod 제거 완료"
  else
    warn "kubectl 접근 불가 → GPU Plugin 제거 스킵"
  fi
}

rollback_04() {
  log "--- [04단계 롤백] Worker 노드 제거 ---"

  # master에서 worker drain & delete
  if kubectl get nodes &>/dev/null; then
    for vm in "${VM_NAMES[@]}"; do
      [[ "$vm" == "k8s-master" ]] && continue
      kubectl drain "$vm" --ignore-daemonsets --delete-emptydir-data --force \
        2>/dev/null || true
      kubectl delete node "$vm" --ignore-not-found=true 2>/dev/null || true
      log "   노드 $vm 삭제 완료"
    done
  else
    warn "kubectl 접근 불가 → 노드 삭제 스킵"
  fi

  # 각 worker VM에서 kubeadm reset
  if [[ -f "$VM_IPS_ENV" ]]; then
    source "$VM_IPS_ENV"
    for WORKER_VAR in WORKER1_IP WORKER2_IP; do
      WORKER_IP="${!WORKER_VAR}"
      [[ -z "$WORKER_IP" || "$WORKER_IP" == "unknown" ]] && continue
      log "   $WORKER_VAR ($WORKER_IP) → kubeadm reset 중..."
      ssh $SSH_OPTS "ubuntu@${WORKER_IP}" \
        "sudo kubeadm reset --force --cri-socket=unix:///run/containerd/containerd.sock 2>/dev/null; \
         sudo rm -rf /etc/cni/net.d /var/lib/cni 2>/dev/null; \
         sudo iptables -F; sudo iptables -t nat -F" \
        2>/dev/null \
        || warn "$WORKER_IP kubeadm reset 실패 (수동 확인 필요)"
    done
  else
    warn "vm_ips.env 없음 → worker kubeadm reset 스킵 (VM에서 수동 실행 필요)"
  fi
}

rollback_03() {
  log "--- [03단계 롤백] Master 클러스터 해체 ---"

  sudo kubeadm reset --force \
    --cri-socket=unix:///run/containerd/containerd.sock 2>/dev/null \
    || warn "kubeadm reset 실패 (이미 초기화 상태일 수 있음)"

  sudo rm -rf /etc/cni/net.d /var/lib/cni 2>/dev/null || true

  sudo iptables -F 2>/dev/null || true
  sudo iptables -X 2>/dev/null || true
  sudo iptables -t nat -F 2>/dev/null || true
  sudo iptables -t nat -X 2>/dev/null || true

  rm -f "$HOME/.kube/config" 2>/dev/null || true
  rmdir "$HOME/.kube" 2>/dev/null || true
  rm -rf "$HOME/k8s-setup" 2>/dev/null || true

  sudo systemctl restart containerd 2>/dev/null \
    || warn "containerd 재시작 실패"

  log "   클러스터 해체 완료"
}

rollback_02() {
  log "--- [02단계 롤백] VM 내부 패키지 제거 ---"
  warn "02_node_setup.sh 는 VM 내부에서 실행된 것으로, 패키지 단위 롤백은 지원하지 않습니다."
  warn "VM을 삭제하고 01_vm_create.sh 재실행을 권장합니다. (01단계 롤백으로 이어서 처리)"
}

rollback_01() {
  log "--- [01단계 롤백] VM 전체 삭제 ---"

  for vm in "${VM_NAMES[@]}"; do
    if sudo virsh dominfo "$vm" &>/dev/null; then
      log "   $vm → 강제 중지 중..."
      sudo virsh destroy "$vm" 2>/dev/null || true
      log "   $vm → 정의 삭제 중..."
      sudo virsh undefine "$vm" --remove-all-storage 2>/dev/null \
        || sudo virsh undefine "$vm" 2>/dev/null \
        || warn "$vm undefine 실패"
      log "   $vm 삭제 완료"
    else
      log "   $vm 존재하지 않음 (스킵)"
    fi
    sudo rm -f "$VM_DIR/${vm}.qcow2" 2>/dev/null || true
  done

  # cloud-init 임시 파일 정리 (cloud image, host_info.env 는 보존)
  sudo rm -f  "$SETUP_DIR"/*-seed.iso   2>/dev/null || true
  sudo rm -rf "$SETUP_DIR"/cloud-init-* 2>/dev/null || true
  sudo rm -f  "$SETUP_DIR/vm_ips.env"  2>/dev/null || true

  log "   VM 삭제 완료"
  log "   보존: $SETUP_DIR/ubuntu-24.04-cloud.img"
  log "   보존: $SETUP_DIR/host_info.env"
}

# ────────────────────────────────────────────
# 선택에 따라 역순 누적 실행
# (입력한 단계 포함 이후를 모두 제거)
# ────────────────────────────────────────────
[[ "$CHOICE" -le 5 ]] && rollback_05
[[ "$CHOICE" -le 4 ]] && rollback_04
[[ "$CHOICE" -le 3 ]] && rollback_03
[[ "$CHOICE" -le 2 ]] && rollback_02   # 경고 출력 후 rollback_01로 이어짐
[[ "$CHOICE" -le 2 ]] && rollback_01

# ────────────────────────────────────────────
# 완료
# ────────────────────────────────────────────
echo ""
log "=== 롤백 완료 ==="
echo ""
echo "재시작 위치:"
case "$CHOICE" in
  5) echo "   bash 05_gpu_plugin.sh" ;;
  4) echo "   worker VM에서: bash 04_worker_join.sh" ;;
  3) echo "   master VM에서: bash 03_master_init.sh" ;;
  1|2) echo "   호스트에서:    bash 01_vm_create.sh" ;;
esac
echo ""
