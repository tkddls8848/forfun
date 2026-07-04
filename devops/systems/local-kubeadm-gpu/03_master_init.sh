#!/usr/bin/env bash
set -euo pipefail

SINGLE_NODE="${SINGLE_NODE:-false}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
FLANNEL_VERSION="${FLANNEL_VERSION:-v0.28.5}"
K8S_SETUP_DIR="$HOME/k8s-setup"

log() { echo "[$(date '+%H:%M:%S')] $1"; }
error_exit() { echo "ERROR: $1" >&2; exit 1; }

log "Phase 3: master init"
log "single node mode: $SINGLE_NODE"

kubeadm version >/dev/null 2>&1 || error_exit "kubeadm not found. Run 02_node_setup.sh first."
systemctl is-active --quiet containerd || error_exit "containerd is not active."

sudo kubeadm init \
  --pod-network-cidr="$POD_CIDR" \
  --cri-socket=unix:///run/containerd/containerd.sock \
  | tee /tmp/kubeadm_init.log

mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

kubectl apply -f "https://github.com/flannel-io/flannel/releases/download/${FLANNEL_VERSION}/kube-flannel.yml"

if [[ "$SINGLE_NODE" == "true" ]]; then
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
else
  log "multi-node mode: keeping control-plane taint"
fi

mkdir -p "$K8S_SETUP_DIR"
kubeadm token create --print-join-command | tee "$K8S_SETUP_DIR/worker_join.sh"
chmod +x "$K8S_SETUP_DIR/worker_join.sh"

log "waiting for master Ready state"
for i in $(seq 1 36); do
  status="$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | head -1 || true)"
  echo "  [$i/36] node status: ${status:-Initializing}"
  [[ "$status" == "Ready" ]] && break
  sleep 5
done

kubectl get nodes -o wide
echo "Worker join command:"
cat "$K8S_SETUP_DIR/worker_join.sh"
