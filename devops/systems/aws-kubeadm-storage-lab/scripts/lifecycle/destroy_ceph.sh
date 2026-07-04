#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [1/3] ?∏ÌîÑ???ïÎ≥¥ ?òÏßë"
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
echo " [2/3] Bastion ?òÍ≤Ω Ï§ÄÎπ?
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP "mkdir -p ~/scripts"
printf "SSH_KEY=\$HOME/.ssh/storage-lab.pem
M1_PUB=%s
M1_PRIV=%s
WORKER_PUBS=(%s)
WORKER_PRIVS=(%s)
" \
  "$MASTER_IP" "$MASTER_IP" \
  "${WORKER_IPS[*]}" "${WORKER_IPS[*]}" \
  | ssh $SSH_OPTS ubuntu@$BASTION_IP "cat > ~/scripts/.env"

# kubectl ?§Ïπò (?ÜÎäî Í≤ΩÏö∞)
ssh $SSH_OPTS ubuntu@$BASTION_IP "
  if ! command -v kubectl &>/dev/null; then
    curl -sLO https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
  fi
"

echo "=============================="
echo " [3/3] rook-ceph ??†ú (Bastion?êÏÑú ?§Ìñâ)"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP << 'REMOTE'
set -e
export KUBECONFIG=~/.kube/config-k8s-storage-lab
source ~/scripts/.env
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"
WORKER_COUNT=${#WORKER_PUBS[@]}

echo "=============================="
echo " [1/5] API ?úÎ≤Ñ ?∞Í≤∞ ?ïÏù∏"
echo "=============================="
API_OK=false
if kubectl cluster-info --request-timeout=10s &>/dev/null; then
  echo "  ??API ?úÎ≤Ñ ?ëÎãµ ?ïÏù∏"
  API_OK=true
else
  echo "  ?†Ô∏è  API ?úÎ≤Ñ ?ëÎãµ ?ÜÏùå - K8s Î¶¨ÏÜå????†ú ?®Í≥Ñ ?§ÌÇµ"
fi

echo "=============================="
echo " [2/5] StorageClass ??†ú"
echo "=============================="
if $API_OK; then
  kubectl delete storageclass ceph-rbd ceph-cephfs --ignore-not-found
  echo "  ??StorageClass ??†ú ?ÑÎ£å"
else
  echo "  ?§ÌÇµ (API ?úÎ≤Ñ ÎØ∏Ïùë??"
fi

echo "=============================="
echo " [3/5] CephFilesystem / CephBlockPool ??†ú"
echo "=============================="
if $API_OK; then
  kubectl -n rook-ceph delete cephfilesystem labfs --ignore-not-found
  kubectl -n rook-ceph delete cephblockpool replicapool --ignore-not-found
  echo "  [?ÄÍ∏? ??†ú ?ÄÍ∏?(30s)..."
  sleep 30
  echo "  ??CephFilesystem/BlockPool ??†ú ?ÑÎ£å"
else
  echo "  ?§ÌÇµ (API ?úÎ≤Ñ ÎØ∏Ïùë??"
fi

echo "=============================="
echo " [4/5] CephCluster ??†ú"
echo "=============================="
if $API_OK; then
  kubectl -n rook-ceph patch cephcluster rook-ceph \
    --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  kubectl -n rook-ceph delete cephcluster rook-ceph --ignore-not-found
  sleep 30

  $CSSH$M1_PUB "helm uninstall rook-ceph -n rook-ceph 2>/dev/null || true"
  kubectl delete namespace rook-ceph --ignore-not-found
  sleep 20

  kubectl get crd | grep ceph | awk '{print $1}' | xargs kubectl delete crd --ignore-not-found 2>/dev/null || true
  echo "  ??CephCluster / namespace / CRD ??†ú ?ÑÎ£å"
else
  echo "  ?§ÌÇµ (API ?úÎ≤Ñ ÎØ∏Ïùë??"
fi

echo "=============================="
echo " [5/5] Worker OSD ?îÏä§??Ï¥àÍ∏∞??(nvme1n1, nvme2n1)"
echo "=============================="
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  NODE_IP="${WORKER_PUBS[$i]}"
  NODE_NAME="worker-$((i + 1))"
  echo "  $NODE_NAME ($NODE_IP) ?îÏä§??Ï¥àÍ∏∞??Ï§?.."
  $CSSH$NODE_IP "
    for dev in /dev/nvme1n1 /dev/nvme2n1 /dev/xvdb /dev/xvdc; do
      [ -b \"\$dev\" ] || continue
      echo \"  wipe: \$dev\"
      sudo sgdisk --zap-all \"\$dev\" 2>/dev/null || true
      sudo dd if=/dev/zero of=\"\$dev\" bs=1M count=100 2>/dev/null || true
    done
    sudo dmsetup remove_all 2>/dev/null || true
    sudo rm -rf /var/lib/rook
    echo '  ???îÏä§??Ï¥àÍ∏∞???ÑÎ£å'
  "
done

echo ""
echo "??rook-ceph ??†ú ?ÑÎ£å"
echo "   ?¨ÏÑ§Ïπ? bash scripts/lifecycle/start_ceph.sh"
REMOTE
