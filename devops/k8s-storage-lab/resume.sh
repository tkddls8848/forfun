#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
TAG_FILTER="Name=tag:Name,Values=k8s-storage-lab-*"

echo "=============================="
echo " EC2 시작"
echo "=============================="
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "$TAG_FILTER" "Name=instance-state-name,Values=stopped" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text | tr '\t' ' ')

if [ -z "$INSTANCE_IDS" ]; then
  echo "  중지된 인스턴스가 없습니다."
  aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "$TAG_FILTER" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],State.Name,PublicIpAddress,PrivateIpAddress]' \
    --output table
  exit 0
fi

echo "  시작 대상: $INSTANCE_IDS"
aws ec2 start-instances --region $AWS_REGION --instance-ids $INSTANCE_IDS > /dev/null

echo -n "  실행 대기 중..."
aws ec2 wait instance-running --region $AWS_REGION --instance-ids $INSTANCE_IDS
echo " ✓"

sleep 10  # IP 할당 안정화 대기

echo "=============================="
echo " Bastion IP 갱신"
echo "=============================="
BASTION_IP=$(tofu -chdir="$SCRIPT_DIR/opentofu" output -raw bastion_public_ip)
BASTION_PRIVATE_IP=$(tofu -chdir="$SCRIPT_DIR/opentofu" output -raw bastion_private_ip)
echo "  Bastion Public  : $BASTION_IP"
echo "  Bastion Private : $BASTION_PRIVATE_IP"

echo "=============================="
echo " Bastion SSH 대기"
echo "=============================="
echo -n "  연결 대기 중..."
until ssh $SSH_OPTS ubuntu@$BASTION_IP "echo ok" &>/dev/null; do
  echo -n "."; sleep 5
done
echo " ✓"

echo "=============================="
echo " Playbook 재전송 (최신 상태 반영)"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP "rm -rf ~/ansible ~/manifests"
scp -O $SSH_OPTS -r "$SCRIPT_DIR/ansible"   ubuntu@$BASTION_IP:~/
scp -O $SSH_OPTS -r "$SCRIPT_DIR/manifests" ubuntu@$BASTION_IP:~/

echo ""
echo "=============================="
echo " 현재 노드 상태"
echo "=============================="
aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "$TAG_FILTER" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],PrivateIpAddress,State.Name]' \
  --output table

echo ""
echo "✅ 재시작 완료"
echo "   Bastion : ssh -i $SSH_KEY ubuntu@$BASTION_IP"
echo ""
echo "   K8s 플레이북 재실행 필요 시 (bastion에서):"
echo "   cd ~/ansible && /home/ubuntu/.local/bin/ansible-playbook \\"
echo "     -i inventory/aws_ec2.yml playbooks/k8s.yml \\"
echo "     --extra-vars \"control_plane_endpoint=$BASTION_PRIVATE_IP\""
