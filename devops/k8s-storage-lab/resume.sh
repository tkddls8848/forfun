#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -i $SSH_KEY_PATH"

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
  echo "  중지된 인스턴스가 없습니다. (이미 실행 중?)"
  aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "$TAG_FILTER" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],State.Name,PublicIpAddress]' \
    --output table
  exit 0
fi

echo "  시작 대상: $INSTANCE_IDS"
aws ec2 start-instances --region $AWS_REGION --instance-ids $INSTANCE_IDS > /dev/null

echo -n "  실행 대기 중..."
aws ec2 wait instance-running --region $AWS_REGION --instance-ids $INSTANCE_IDS
echo " ✓"

echo "=============================="
echo " 새 퍼블릭 IP 확인"
echo "=============================="
# EC2 재시작 후 퍼블릭 IP가 변경되므로 tofu output으로 갱신
sleep 10  # IP 할당 안정화 대기

aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "$TAG_FILTER" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],PublicIpAddress,PrivateIpAddress]' \
  --output table

echo "=============================="
echo " scripts/.env 재생성"
echo "=============================="
M1_PUB=$(tofu -chdir=$SCRIPT_DIR/opentofu output -json master_public_ips  | jq -r '.[0]')
W1_PUB=$(tofu -chdir=$SCRIPT_DIR/opentofu output -json worker_public_ips  | jq -r '.[0]')
W2_PUB=$(tofu -chdir=$SCRIPT_DIR/opentofu output -json worker_public_ips  | jq -r '.[1]')
W3_PUB=$(tofu -chdir=$SCRIPT_DIR/opentofu output -json worker_public_ips  | jq -r '.[2]')
W4_PUB=$(tofu -chdir=$SCRIPT_DIR/opentofu output -json worker_public_ips  | jq -r '.[3]')
N1_PUB=$(tofu -chdir=$SCRIPT_DIR/opentofu output -json nsd_public_ips     | jq -r '.[0]')
N2_PUB=$(tofu -chdir=$SCRIPT_DIR/opentofu output -json nsd_public_ips     | jq -r '.[1]')

M1_PRIV=$(tofu -chdir=$SCRIPT_DIR/opentofu output -json master_private_ips | jq -r '.[0]')
W1_PRIV=$(tofu -chdir=$SCRIPT_DIR/opentofu output -json worker_private_ips | jq -r '.[0]')
W2_PRIV=$(tofu -chdir=$SCRIPT_DIR/opentofu output -json worker_private_ips | jq -r '.[1]')
W3_PRIV=$(tofu -chdir=$SCRIPT_DIR/opentofu output -json worker_private_ips | jq -r '.[2]')
W4_PRIV=$(tofu -chdir=$SCRIPT_DIR/opentofu output -json worker_private_ips | jq -r '.[3]')
N1_PRIV=$(tofu -chdir=$SCRIPT_DIR/opentofu output -json nsd_private_ips    | jq -r '.[0]')
N2_PRIV=$(tofu -chdir=$SCRIPT_DIR/opentofu output -json nsd_private_ips    | jq -r '.[1]')

cat > $SCRIPT_DIR/scripts/.env <<EOF
M1_PUB=$M1_PUB
W1_PUB=$W1_PUB; W2_PUB=$W2_PUB; W3_PUB=$W3_PUB; W4_PUB=$W4_PUB
N1_PUB=$N1_PUB; N2_PUB=$N2_PUB
M1_PRIV=$M1_PRIV
W1_PRIV=$W1_PRIV; W2_PRIV=$W2_PRIV; W3_PRIV=$W3_PRIV; W4_PRIV=$W4_PRIV
N1_PRIV=$N1_PRIV; N2_PRIV=$N2_PRIV
SSH_KEY=$SSH_KEY_PATH
EOF

echo "  scripts/.env 갱신 완료"

echo "=============================="
echo " SSH 접속 확인"
echo "=============================="
ALL_PUB=($M1_PUB $W1_PUB $W2_PUB $W3_PUB $W4_PUB $N1_PUB $N2_PUB)
for ip in "${ALL_PUB[@]}"; do
  echo -n "  $ip 대기 중..."
  until ssh $SSH_OPTS ubuntu@$ip "echo ok" &>/dev/null; do
    echo -n "."; sleep 5
  done
  echo " ✓"
done

echo ""
echo "✅ 재시작 완료"
echo "   master-1 : $M1_PUB"
echo "   worker-1 : $W1_PUB"
echo "   worker-2 : $W2_PUB"
echo "   worker-3 : $W3_PUB"
echo "   worker-4 : $W4_PUB"
echo "   nsd-1    : $N1_PUB"
echo "   nsd-2    : $N2_PUB"
