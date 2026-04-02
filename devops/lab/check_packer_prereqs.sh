#!/bin/bash
# Packer 빌드 사전 조건 점검 스크립트

REGION="${1:-ap-northeast-2}"
KEY_NAME="${2:-storage-lab}"
KEY_FILE="${3:-$HOME/.ssh/storage-lab.pem}"

PASS="[PASS]"
FAIL="[FAIL]"
WARN="[WARN]"

echo "========================================"
echo " Packer 사전 조건 점검"
echo " Region : $REGION"
echo " Key    : $KEY_NAME"
echo " PEM    : $KEY_FILE"
echo "========================================"

# ── 1. Default VPC ───────────────────────────────────────────────────────────
echo ""
echo "[ 1 ] Default VPC"
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
  echo "  $FAIL Default VPC 없음"
  echo "       복구: aws ec2 create-default-vpc --region $REGION"
  VPC_ID=""
else
  echo "  $PASS $VPC_ID"
fi

# ── 2. Subnets ───────────────────────────────────────────────────────────────
echo ""
echo "[ 2 ] Subnets (Default VPC)"
if [ -z "$VPC_ID" ]; then
  echo "  $WARN VPC 없으므로 서브넷 검사 생략"
else
  SUBNETS=$(aws ec2 describe-subnets --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[*].{ID:SubnetId,AZ:AvailabilityZone}' \
    --output text 2>/dev/null)
  if [ -z "$SUBNETS" ]; then
    echo "  $FAIL 서브넷 없음"
    echo "       복구 예시:"
    echo "         aws ec2 create-default-subnet --availability-zone ${REGION}a --region $REGION"
    echo "         aws ec2 create-default-subnet --availability-zone ${REGION}b --region $REGION"
    echo "         aws ec2 create-default-subnet --availability-zone ${REGION}c --region $REGION"
  else
    while IFS= read -r line; do
      echo "  $PASS $line"
    done <<< "$SUBNETS"
  fi
fi

# ── 3. Internet Gateway ──────────────────────────────────────────────────────
echo ""
echo "[ 3 ] Internet Gateway"
if [ -z "$VPC_ID" ]; then
  echo "  $WARN VPC 없으므로 IGW 검사 생략"
else
  IGW=$(aws ec2 describe-internet-gateways --region "$REGION" \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null)
  if [ "$IGW" = "None" ] || [ -z "$IGW" ]; then
    echo "  $FAIL IGW 없음"
    echo "       복구:"
    echo "         IGW_ID=\$(aws ec2 create-internet-gateway --region $REGION --query 'InternetGateway.InternetGatewayId' --output text)"
    echo "         aws ec2 attach-internet-gateway --region $REGION --internet-gateway-id \$IGW_ID --vpc-id $VPC_ID"
  else
    echo "  $PASS $IGW"
  fi
fi

# ── 4. Route Table (0.0.0.0/0 → IGW) + IGW 일치 검사 ────────────────────────
echo ""
echo "[ 4 ] Route Table (0.0.0.0/0 → IGW) + IGW 일치"
if [ -z "$VPC_ID" ]; then
  echo "  $WARN VPC 없으므로 라우팅 검사 생략"
else
  RT_ID=$(aws ec2 describe-route-tables --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
    --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null)
  DEFAULT_ROUTE=$(aws ec2 describe-route-tables --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "RouteTables[*].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId" \
    --output text 2>/dev/null)

  if ! echo "$DEFAULT_ROUTE" | grep -q "igw-"; then
    echo "  $FAIL 기본 경로(0.0.0.0/0) 없음"
    echo "       복구: aws ec2 create-route --region $REGION --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW"
  elif [ "$DEFAULT_ROUTE" != "$IGW" ]; then
    echo "  $FAIL 라우팅 IGW($DEFAULT_ROUTE) ≠ 부착된 IGW($IGW) — 불일치!"
    echo "       복구:"
    echo "         aws ec2 delete-route --region $REGION --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0"
    echo "         aws ec2 create-route --region $REGION --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW"
  else
    echo "  $PASS 0.0.0.0/0 → $DEFAULT_ROUTE (부착된 IGW 일치)"
  fi
fi

# ── 5. SSH Key Pair (AWS) ────────────────────────────────────────────────────
echo ""
echo "[ 5 ] SSH Key Pair (AWS EC2)"
KEY_EXISTS=$(aws ec2 describe-key-pairs --region "$REGION" \
  --key-names "$KEY_NAME" \
  --query 'KeyPairs[0].KeyName' --output text 2>/dev/null)
if [ "$KEY_EXISTS" = "$KEY_NAME" ]; then
  echo "  $PASS $KEY_NAME"
else
  echo "  $FAIL Key Pair '$KEY_NAME' 가 AWS에 없음"
  echo "       EC2 콘솔 또는 CLI로 키 페어를 생성/등록하세요"
fi

# ── 6. PEM 파일 (로컬) ───────────────────────────────────────────────────────
echo ""
echo "[ 6 ] PEM 파일 (로컬)"
EXPANDED_KEY="${KEY_FILE/#\~/$HOME}"
if [ -f "$EXPANDED_KEY" ]; then
  PERMS=$(stat -c "%a" "$EXPANDED_KEY" 2>/dev/null)
  if [ "$PERMS" = "400" ] || [ "$PERMS" = "600" ]; then
    echo "  $PASS $EXPANDED_KEY (권한: $PERMS)"
  else
    echo "  $WARN $EXPANDED_KEY 존재하지만 권한이 $PERMS (400 권장)"
    echo "       복구: chmod 400 $EXPANDED_KEY"
  fi
else
  echo "  $FAIL $EXPANDED_KEY 없음"
  echo "       AWS에서 키 페어 다운로드 후 ~/.ssh/ 에 배치하세요"
fi

echo ""
echo "========================================"
echo " 점검 완료"
echo "========================================"
