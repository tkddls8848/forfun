#!/bin/bash
# HCI Worker 노드 1대 제거 (마지막 노드 drain → delete → tofu)
# 사용법: bash worker_remove.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"
KUBECONFIG_PATH="~/.kube/config-k8s-storage-lab"

echo "=============================="
echo " [0/5] 사전 요구사항 확인"
echo "=============================="
for cmd in tofu jq ssh; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ $cmd 가 없습니다."; exit 1
  fi
done

cd "$SCRIPT_DIR/opentofu"
CURRENT=$(tofu output -json worker_private_ips | jq 'length')

if [ "$CURRENT" -le 1 ]; then
  echo "❌ Worker가 1대 이하입니다. 최소 1대 유지 필요."; exit 1
fi

NEW_COUNT=$((CURRENT - 1))
TARGET_IP=$(tofu output -json worker_private_ips | jq -r ".[$NEW_COUNT]")
TARGET_NAME="worker-$CURRENT"
BASTION_IP=$(tofu output -raw bastion_public_ip)

echo "  제거 대상: $TARGET_NAME ($TARGET_IP)"
echo "  제거 후 Worker 수: $NEW_COUNT"
read -p "  계속하시겠습니까? [y/N] " confirm
[ "$confirm" != "y" ] && echo "취소됨" && exit 0

echo "=============================="
echo " [1/5] BeeGFS storaged 컨테이너 확인"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "export KUBECONFIG=$KUBECONFIG_PATH && \
   kubectl -n beegfs-system get pods -o wide | grep $TARGET_IP || true"

echo "=============================="
echo " [2/5] K8s 노드 drain"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "export KUBECONFIG=$KUBECONFIG_PATH && \
   kubectl drain $TARGET_NAME \
     --ignore-daemonsets \
     --delete-emptydir-data \
     --force \
     --timeout=120s"

echo "=============================="
echo " [3/5] Ceph OSD 안전 제거"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP "
export KUBECONFIG=$KUBECONFIG_PATH

# 해당 worker의 OSD ID 찾기
OSD_IDS=\$(kubectl -n rook-ceph get pods -o wide | grep $TARGET_IP | grep osd | awk '{print \$1}' | grep -oP 'osd-\K[0-9]+' || echo '')

if [ -n \"\$OSD_IDS\" ]; then
  for OSD_ID in \$OSD_IDS; do
    echo \"  OSD \$OSD_ID 제거 중...\"
    # out → down → purge
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd out \$OSD_ID
    sleep 5
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd down \$OSD_ID
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd purge \$OSD_ID --yes-i-really-mean-it
    echo \"  ✅ OSD \$OSD_ID 제거 완료\"
  done
  echo \"  Ceph rebalancing 대기 (60s)...\"
  sleep 60
  kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
else
  echo \"  OSD 없음 - 건너뜀\"
fi
"

echo "=============================="
echo " [4/5] K8s 노드 삭제"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "export KUBECONFIG=$KUBECONFIG_PATH && \
   kubectl delete node $TARGET_NAME"

# known_hosts 정리
ssh-keygen -R "$TARGET_IP" 2>/dev/null || true

echo "=============================="
echo " [5/5] 인프라 축소 (tofu apply)"
echo "=============================="
tofu apply -auto-approve -var="worker_count=$NEW_COUNT"

echo ""
echo "✅ Worker 제거 완료!"
echo "   제거된 노드: $TARGET_NAME ($TARGET_IP)"
echo "   현재 Worker 수: $NEW_COUNT"
echo "   kubectl get nodes"
