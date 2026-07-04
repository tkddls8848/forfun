#!/bin/bash
# HCI Worker ?¸ë“œ 1?€ ?œê±° (ë§ˆì?ë§??¸ë“œ drain ??delete ??tofu)
# ?¬ìš©ë²? bash scripts/lifecycle/worker_remove.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"
KUBECONFIG_PATH="~/.kube/config-k8s-storage-lab"

echo "=============================="
echo " [0/5] ?¬ì „ ?”êµ¬?¬í•­ ?•ì¸"
echo "=============================="
for cmd in tofu jq ssh; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "??$cmd ê°€ ?†ìŠµ?ˆë‹¤."; exit 1
  fi
done

cd "$LAB_ROOT/opentofu"
CURRENT=$(tofu output -json worker_private_ips | jq 'length')

if [ "$CURRENT" -le 1 ]; then
  echo "??Workerê°€ 1?€ ?´í•˜?…ë‹ˆ?? ìµœì†Œ 1?€ ? ì? ?„ìš”."; exit 1
fi

NEW_COUNT=$((CURRENT - 1))
TARGET_IP=$(tofu output -json worker_private_ips | jq -r ".[$NEW_COUNT]")
TARGET_NAME="worker-$CURRENT"
BASTION_IP=$(tofu output -raw bastion_public_ip)

echo "  ?œê±° ?€?? $TARGET_NAME ($TARGET_IP)"
echo "  ?œê±° ??Worker ?? $NEW_COUNT"
read -p "  ê³„ì†?˜ì‹œê² ìŠµ?ˆê¹Œ? [y/N] " confirm
[ "$confirm" != "y" ] && echo "ì·¨ì†Œ?? && exit 0

echo "=============================="
echo " [1/5] BeeGFS storaged ì»¨í…Œ?´ë„ˆ ?•ì¸"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "export KUBECONFIG=$KUBECONFIG_PATH && \
   kubectl -n beegfs-system get pods -o wide | grep $TARGET_IP || true"

echo "=============================="
echo " [2/5] K8s ?¸ë“œ drain"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "export KUBECONFIG=$KUBECONFIG_PATH && \
   kubectl drain $TARGET_NAME \
     --ignore-daemonsets \
     --delete-emptydir-data \
     --force \
     --timeout=120s"

echo "=============================="
echo " [3/5] Ceph OSD ?ˆì „ ?œê±°"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP "
export KUBECONFIG=$KUBECONFIG_PATH

# ?´ë‹¹ worker??OSD ID ì°¾ê¸°
OSD_IDS=\$(kubectl -n rook-ceph get pods -o wide | grep $TARGET_IP | grep osd | awk '{print \$1}' | grep -oP 'osd-\K[0-9]+' || echo '')

if [ -n \"\$OSD_IDS\" ]; then
  for OSD_ID in \$OSD_IDS; do
    echo \"  OSD \$OSD_ID ?œê±° ì¤?..\"
    # out ??down ??purge
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd out \$OSD_ID
    sleep 5
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd down \$OSD_ID
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd purge \$OSD_ID --yes-i-really-mean-it
    echo \"  ??OSD \$OSD_ID ?œê±° ?„ë£Œ\"
  done
  echo \"  Ceph rebalancing ?€ê¸?(60s)...\"
  sleep 60
  kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
else
  echo \"  OSD ?†ìŒ - ê±´ë„ˆ?€\"
fi
"

echo "=============================="
echo " [4/5] K8s ?¸ë“œ ?? œ"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "export KUBECONFIG=$KUBECONFIG_PATH && \
   kubectl delete node $TARGET_NAME"

# known_hosts ?•ë¦¬
ssh-keygen -R "$TARGET_IP" 2>/dev/null || true

echo "=============================="
echo " [5/5] ?¸í”„??ì¶•ì†Œ (tofu apply)"
echo "=============================="
tofu apply -auto-approve -var="worker_count=$NEW_COUNT"

echo ""
echo "??Worker ?œê±° ?„ë£Œ!"
echo "   ?œê±°???¸ë“œ: $TARGET_NAME ($TARGET_IP)"
echo "   ?„ìž¬ Worker ?? $NEW_COUNT"
echo "   kubectl get nodes"
