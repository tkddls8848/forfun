#!/bin/bash
# k3s-storage-lab EC2 인스턴스 중지 (EBS 데이터 유지)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="k3s-storage-lab"
REGION=$(grep aws_region "$SCRIPT_DIR/opentofu/terraform.tfvars" | awk -F'"' '{print $2}')

echo "=============================="
echo " EC2 인스턴스 중지"
echo "=============================="

INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters \
    "Name=tag:Name,Values=${PROJECT_NAME}-frontend,${PROJECT_NAME}-backend" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "실행 중인 인스턴스가 없습니다."
  exit 0
fi

echo "  중지 대상: $INSTANCE_IDS"
aws ec2 stop-instances --region "$REGION" --instance-ids $INSTANCE_IDS > /dev/null

echo "  중지 완료 대기..."
aws ec2 wait instance-stopped --region "$REGION" --instance-ids $INSTANCE_IDS

echo "✅ 인스턴스 중지 완료 (EBS 데이터 유지)"
echo "   재시작: bash restart.sh"
