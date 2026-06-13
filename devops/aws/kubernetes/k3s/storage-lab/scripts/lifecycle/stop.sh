#!/bin/bash
# k3s-storage-lab EC2 ?¸ìŠ¤?´ìŠ¤ ì¤‘ì? (EBS ?°ì´??? ì?)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_NAME="k3s-storage-lab"
REGION=$(grep aws_region "$LAB_ROOT/opentofu/terraform.tfvars" | awk -F'"' '{print $2}')

echo "=============================="
echo " EC2 ?¸ìŠ¤?´ìŠ¤ ì¤‘ì?"
echo "=============================="

INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters \
    "Name=tag:Name,Values=${PROJECT_NAME}-frontend,${PROJECT_NAME}-backend" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "?¤í–‰ ì¤‘ì¸ ?¸ìŠ¤?´ìŠ¤ê°€ ?†ìŠµ?ˆë‹¤."
  exit 0
fi

echo "  ì¤‘ì? ?€?? $INSTANCE_IDS"
aws ec2 stop-instances --region "$REGION" --instance-ids $INSTANCE_IDS > /dev/null

echo "  ì¤‘ì? ?„ë£Œ ?€ê¸?.."
aws ec2 wait instance-stopped --region "$REGION" --instance-ids $INSTANCE_IDS

echo "???¸ìŠ¤?´ìŠ¤ ì¤‘ì? ?„ë£Œ (EBS ?°ì´??? ì?)"
echo "   ?¬ì‹œ?? bash restart.sh"
