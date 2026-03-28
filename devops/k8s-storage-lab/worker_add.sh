#!/bin/bash
# HCI Worker 노드 1대 추가 (K8s + Ceph OSD + BeeGFS storaged)
# 사용법: bash worker_add.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [0/4] 사전 요구사항 확인"
echo "=============================="
for cmd in tofu jq ssh; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ $cmd 가 없습니다."; exit 1
  fi
done
if [ ! -f "$SSH_KEY" ]; then
  echo "❌ SSH 키가 없습니다: $SSH_KEY"; exit 1
fi

cd "$SCRIPT_DIR/opentofu"

# 현재 worker_count 읽기
CURRENT=$(tofu output -json worker_private_ips | jq 'length')
NEW_COUNT=$((CURRENT + 1))
echo "  현재 Worker 수: $CURRENT → 추가 후: $NEW_COUNT"

echo "=============================="
echo " [1/4] 인프라 확장 (tofu apply)"
echo "=============================="
tofu apply -auto-approve -var="worker_count=$NEW_COUNT"

BASTION_IP=$(tofu output -raw bastion_public_ip)
BASTION_PRIVATE_IP=$(tofu output -raw bastion_private_ip)

# 새 worker의 private IP (마지막 항목)
NEW_WORKER_IP=$(tofu output -json worker_private_ips | jq -r ".[$CURRENT]")
echo "  새 Worker IP: $NEW_WORKER_IP"

echo "=============================="
echo " [2/4] 새 Worker 부팅 대기"
echo "=============================="
echo -n "  $NEW_WORKER_IP 대기 중..."
until ssh $SSH_OPTS -o "ProxyCommand=ssh $SSH_OPTS -W %h:%p ubuntu@$BASTION_IP" \
  ubuntu@$NEW_WORKER_IP "echo ok" &>/dev/null; do
  echo -n "."; sleep 5
done
echo " ✓"

echo "=============================="
echo " [3/4] Ansible: 새 Worker 설정 + K8s/BeeGFS join"
echo "=============================="
# ansible + manifests 재전송 (최신 상태 반영)
scp -O $SSH_OPTS -r "$SCRIPT_DIR/ansible"   ubuntu@$BASTION_IP:~/
scp -O $SSH_OPTS -r "$SCRIPT_DIR/manifests" ubuntu@$BASTION_IP:~/

ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "cd ~/ansible && /home/ubuntu/.local/bin/ansible-playbook \
     -i inventory/aws_ec2.yml playbooks/k8s.yml \
     --extra-vars \"control_plane_endpoint=$BASTION_PRIVATE_IP\" \
     --limit \"$NEW_WORKER_IP\" \
     --tags common,hci_node,cluster_setup,kubernetes_common,kubernetes_worker"

echo "=============================="
echo " [4/4] BeeGFS storaged join"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "cd ~/ansible && /home/ubuntu/.local/bin/ansible-playbook \
     -i inventory/aws_ec2.yml playbooks/beegfs.yml \
     --limit \"$NEW_WORKER_IP\""

echo ""
echo "✅ Worker 추가 완료!"
echo "   새 노드: $NEW_WORKER_IP (worker-$NEW_COUNT)"
echo "   Ceph OSD는 rook-ceph operator가 자동으로 새 디스크를 감지합니다."
echo "   kubectl get nodes"
echo "   kubectl -n rook-ceph get pods -o wide"
