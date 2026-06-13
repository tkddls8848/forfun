#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [1/3] ?¸í”„???•ë³´ ?˜ì§‘"
echo "=============================="
cd "$LAB_ROOT/opentofu"
BASTION_IP=$(tofu output -raw bastion_public_ip)
MASTER_IP=$(tofu output -json master_private_ips | jq -r '.[0]')
WORKER_IPS=($(tofu output -json worker_private_ips | jq -r '.[]'))
cd "$LAB_ROOT"

echo "  Bastion : $BASTION_IP"
echo "  Master  : $MASTER_IP"
echo "  Workers : ${WORKER_IPS[*]}"

echo "=============================="
echo " [2/3] Bastion ?˜ê²½ ì¤€ë¹?
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP "mkdir -p ~/scripts"
printf "SSH_KEY=\$HOME/.ssh/storage-lab.pem
MASTER_IP=%s
WORKER_IPS=(%s)
" \
  "$MASTER_IP" \
  "${WORKER_IPS[*]}" \
  | ssh $SSH_OPTS ubuntu@$BASTION_IP "cat > ~/scripts/.env"

# kubectl ?¤ì¹˜ (?†ëŠ” ê²½ìš°)
ssh $SSH_OPTS ubuntu@$BASTION_IP "
  if ! command -v kubectl &>/dev/null; then
    curl -sLO https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
  fi
"

echo "=============================="
echo " [3/3] BeeGFS ?? œ (Bastion?ì„œ ?¤í–‰)"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP << 'REMOTE'
set -e
export KUBECONFIG=~/.kube/config-k8s-storage-lab
source ~/scripts/.env
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"
WORKER_COUNT=${#WORKER_IPS[@]}

echo "=============================="
echo " [1/5] API ?œë²„ ?°ê²° ?•ì¸"
echo "=============================="
API_OK=false
if kubectl cluster-info --request-timeout=10s &>/dev/null; then
  echo "  ??API ?œë²„ ?‘ë‹µ ?•ì¸"
  API_OK=true
else
  echo "  ? ï¸  API ?œë²„ ?‘ë‹µ ?†ìŒ - K8s ë¦¬ì†Œ???? œ ?¨ê³„ ?¤í‚µ"
fi

echo "=============================="
echo " [2/5] StorageClass ?? œ"
echo "=============================="
if $API_OK; then
  kubectl delete storageclass beegfs-scratch --ignore-not-found
  echo "  ??StorageClass ?? œ ?„ë£Œ"
else
  echo "  ?¤í‚µ (API ?œë²„ ë¯¸ì‘??"
fi

echo "=============================="
echo " [3/5] beegfs-system ?¤ì„?¤í˜?´ìŠ¤ ë¦¬ì†Œ???? œ"
echo "=============================="
if $API_OK; then
  # Deployment / DaemonSet / Service / ServiceMonitor / ConfigMap
  kubectl delete deployment beegfs-mgmtd beegfs-meta beegfs-exporter \
    -n beegfs-system --ignore-not-found
  kubectl delete daemonset beegfs-storage \
    -n beegfs-system --ignore-not-found
  kubectl delete service beegfs-mgmtd beegfs-meta beegfs-exporter \
    -n beegfs-system --ignore-not-found
  kubectl delete servicemonitor beegfs-exporter \
    -n beegfs-system --ignore-not-found 2>/dev/null || true
  kubectl delete configmap beegfs-exporter-script \
    -n beegfs-system --ignore-not-found
  echo "  [?€ê¸? Pod ì¢…ë£Œ ?€ê¸?(20s)..."
  sleep 20
  echo "  ??beegfs-system ë¦¬ì†Œ???? œ ?„ë£Œ"
else
  echo "  ?¤í‚µ (API ?œë²„ ë¯¸ì‘??"
fi

echo "=============================="
echo " [4/5] Grafana ?€?œë³´??ConfigMap ?? œ"
echo "=============================="
if $API_OK; then
  kubectl delete configmap beegfs-grafana-dashboard \
    -n monitoring --ignore-not-found
  echo "  ??Grafana ?€?œë³´??ConfigMap ?? œ ?„ë£Œ"
else
  echo "  ?¤í‚µ (API ?œë²„ ë¯¸ì‘??"
fi

echo "=============================="
echo " [5/5] beegfs-system ?¤ì„?¤í˜?´ìŠ¤ ?? œ"
echo "=============================="
if $API_OK; then
  kubectl delete namespace beegfs-system --ignore-not-found
  echo "  [?€ê¸? ?¤ì„?¤í˜?´ìŠ¤ ?? œ ?€ê¸?(20s)..."
  sleep 20
  echo "  ???¤ì„?¤í˜?´ìŠ¤ ?? œ ?„ë£Œ"
else
  echo "  ?¤í‚µ (API ?œë²„ ë¯¸ì‘??"
fi

echo ""
echo "??BeeGFS ?? œ ?„ë£Œ"
echo "   ?¬ì„¤ì¹? bash scripts/lifecycle/start_beegfs.sh"
REMOTE
