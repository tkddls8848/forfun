#!/bin/bash
# HCI Worker ?∏Îìú 1?Ä Ï∂îÍ? (K8s + Ceph OSD + BeeGFS storaged)
# ?¨Ïö©Î≤? bash scripts/lifecycle/worker_add.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [0/4] ?¨Ï†Ñ ?îÍµ¨?¨Ìï≠ ?ïÏù∏"
echo "=============================="
for cmd in tofu jq ssh; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "??$cmd Í∞Ä ?ÜÏäµ?àÎã§."; exit 1
  fi
done
if [ ! -f "$SSH_KEY" ]; then
  echo "??SSH ?§Í? ?ÜÏäµ?àÎã§: $SSH_KEY"; exit 1
fi

cd "$LAB_ROOT/opentofu"

# ?ÑÏû¨ worker_count ?ΩÍ∏∞
CURRENT=$(tofu output -json worker_private_ips | jq 'length')
NEW_COUNT=$((CURRENT + 1))
echo "  ?ÑÏû¨ Worker ?? $CURRENT ??Ï∂îÍ? ?? $NEW_COUNT"

echo "=============================="
echo " [1/4] ?∏ÌîÑ???ïÏû• (tofu apply)"
echo "=============================="
tofu apply -auto-approve -var="worker_count=$NEW_COUNT"

BASTION_IP=$(tofu output -raw bastion_public_ip)
BASTION_PRIVATE_IP=$(tofu output -raw bastion_private_ip)

# ??worker??private IP (ÎßàÏ?Îß???™©)
NEW_WORKER_IP=$(tofu output -json worker_private_ips | jq -r ".[$CURRENT]")
echo "  ??Worker IP: $NEW_WORKER_IP"

echo "=============================="
echo " [2/4] ??Worker Î∂Ä???ÄÍ∏?
echo "=============================="
echo -n "  $NEW_WORKER_IP ?ÄÍ∏?Ï§?.."
until ssh $SSH_OPTS -o "ProxyCommand=ssh $SSH_OPTS -W %h:%p ubuntu@$BASTION_IP" \
  ubuntu@$NEW_WORKER_IP "echo ok" &>/dev/null; do
  echo -n "."; sleep 5
done
echo " ??

echo "=============================="
echo " [3/4] Ansible: ??Worker ?§Ï†ï + K8s/BeeGFS join"
echo "=============================="
# ansible + manifests ?¨Ï†Ñ??(ÏµúÏã† ?ÅÌÉú Î∞òÏòÅ)
scp -O $SSH_OPTS -r "$LAB_ROOT/ansible"   ubuntu@$BASTION_IP:~/
scp -O $SSH_OPTS -r "$LAB_ROOT/manifests" ubuntu@$BASTION_IP:~/

ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "cd ~/ansible && /home/ubuntu/.local/bin/ansible-playbook \
     -i inventory/aws_ec2.yml playbooks/k8s.yml \
     --extra-vars \"control_plane_endpoint=$BASTION_PRIVATE_IP\" \
     --limit \"$NEW_WORKER_IP\" \
     --tags common,hci_node,cluster_setup,k8s_common,worker"

echo "=============================="
echo " [4/4] BeeGFS storaged join"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "cd ~/ansible && /home/ubuntu/.local/bin/ansible-playbook \
     -i inventory/aws_ec2.yml playbooks/beegfs.yml \
     --limit \"$NEW_WORKER_IP\""

echo ""
echo "??Worker Ï∂îÍ? ?ÑÎ£å!"
echo "   ???∏Îìú: $NEW_WORKER_IP (worker-$NEW_COUNT)"
echo "   Ceph OSD??rook-ceph operatorÍ∞Ä ?êÎèô?ºÎ°ú ???îÏä§?¨Î? Í∞êÏ??©Îãà??"
echo "   kubectl get nodes"
echo "   kubectl -n rook-ceph get pods -o wide"
