#!/bin/bash
# k3s-storage-lab EC2 ?¸ìŠ¤?´ìŠ¤ ?¬ì‹œ??# - ?œë¹„??k3s, ceph, beegfs)??systemd???±ë¡?˜ì–´ ?ë™ ê¸°ë™
# - Public IPê°€ ë³€ê²½ë˜ë¯€ë¡???IPë¥?ì¶œë ¥
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_NAME="k3s-storage-lab"
REGION=$(grep aws_region "$LAB_ROOT/opentofu/terraform.tfvars" | awk -F'"' '{print $2}')
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " EC2 ?¸ìŠ¤?´ìŠ¤ ?œì‘"
echo "=============================="

INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters \
    "Name=tag:Name,Values=${PROJECT_NAME}-frontend,${PROJECT_NAME}-backend" \
    "Name=instance-state-name,Values=stopped" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "ì¤‘ì????¸ìŠ¤?´ìŠ¤ê°€ ?†ìŠµ?ˆë‹¤. (?´ë? ?¤í–‰ ì¤‘ì´ê±°ë‚˜ ì¡´ì¬?˜ì? ?ŠìŒ)"
  exit 0
fi

echo "  ?œì‘ ?€?? $INSTANCE_IDS"
aws ec2 start-instances --region "$REGION" --instance-ids $INSTANCE_IDS > /dev/null

echo "  ?¸ìŠ¤?´ìŠ¤ running ?€ê¸?.."
aws ec2 wait instance-running --region "$REGION" --instance-ids $INSTANCE_IDS

# ??Public IP ì¡°íšŒ
FRONTEND_IP=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters \
    "Name=tag:Name,Values=${PROJECT_NAME}-frontend" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

BACKEND_IP=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters \
    "Name=tag:Name,Values=${PROJECT_NAME}-backend" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "  Frontend: $FRONTEND_IP"
echo "  Backend : $BACKEND_IP"

echo "=============================="
echo " SSH ?°ê²° ?€ê¸?
echo "=============================="
for IP in $FRONTEND_IP $BACKEND_IP; do
  echo -n "  $IP ?€ê¸?ì¤?.."
  until ssh $SSH_OPTS ec2-user@$IP "echo ok" &>/dev/null; do
    echo -n "."; sleep 5
  done
  echo " ??
done

echo ""
echo "???¸ìŠ¤?´ìŠ¤ ?¬ì‹œ???„ë£Œ"
echo ""
echo "  Frontend : ssh -i $SSH_KEY ec2-user@$FRONTEND_IP"
echo "  Backend  : ssh -i $SSH_KEY ec2-user@$BACKEND_IP"
echo ""
echo "  ?œë¹„???íƒœ ?•ì¸:"
echo "    ssh -i $SSH_KEY ec2-user@$FRONTEND_IP 'kubectl get nodes'"
