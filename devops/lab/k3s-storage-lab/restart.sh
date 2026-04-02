#!/bin/bash
# k3s-storage-lab EC2 인스턴스 재시작
# - 서비스(k3s, ceph, beegfs)는 systemd에 등록되어 자동 기동
# - Public IP가 변경되므로 새 IP를 출력
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="k3s-storage-lab"
REGION=$(grep aws_region "$SCRIPT_DIR/opentofu/terraform.tfvars" | awk -F'"' '{print $2}')
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " EC2 인스턴스 시작"
echo "=============================="

INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters \
    "Name=tag:Name,Values=${PROJECT_NAME}-frontend,${PROJECT_NAME}-backend" \
    "Name=instance-state-name,Values=stopped" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "중지된 인스턴스가 없습니다. (이미 실행 중이거나 존재하지 않음)"
  exit 0
fi

echo "  시작 대상: $INSTANCE_IDS"
aws ec2 start-instances --region "$REGION" --instance-ids $INSTANCE_IDS > /dev/null

echo "  인스턴스 running 대기..."
aws ec2 wait instance-running --region "$REGION" --instance-ids $INSTANCE_IDS

# 새 Public IP 조회
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
echo " SSH 연결 대기"
echo "=============================="
for IP in $FRONTEND_IP $BACKEND_IP; do
  echo -n "  $IP 대기 중..."
  until ssh $SSH_OPTS ubuntu@$IP "echo ok" &>/dev/null; do
    echo -n "."; sleep 5
  done
  echo " ✓"
done

echo ""
echo "✅ 인스턴스 재시작 완료"
echo ""
echo "  Frontend : ssh -i $SSH_KEY ubuntu@$FRONTEND_IP"
echo "  Backend  : ssh -i $SSH_KEY ubuntu@$BACKEND_IP"
echo ""
echo "  서비스 상태 확인:"
echo "    ssh -i $SSH_KEY ubuntu@$FRONTEND_IP 'kubectl get nodes'"
