#!/bin/bash
# 00_build_ami.sh — Packer 사전 조건 점검 + frontend/backend AMI 빌드
# 실행: bash scripts/00_build_ami.sh [REGION] [KEY_NAME] [PEM_FILE]
#
# 통합 내용:
#   check_packer_prereqs.sh  → [1단계] 사전 조건 점검
#   01_k3s_frontend.sh       → Packer frontend 프로비저너 (scripts/frontend.sh)
#   02_ceph_backend.sh       → Packer backend 프로비저너 (scripts/backend.sh) — Ceph
#   03_beegfs_backend.sh     → Packer backend 프로비저너 (scripts/backend.sh) — BeeGFS
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKER_DIR="$LAB_DIR/packer/k3s-storage-lab"

REGION="${1:-ap-northeast-2}"
KEY_NAME="${2:-storage-lab}"
KEY_FILE="${3:-${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}}"
EXPANDED_KEY="${KEY_FILE/#\~/$HOME}"

PASS="[PASS]"
FAIL="[FAIL]"
WARN="[WARN]"
ERRORS=0

# ══════════════════════════════════════════════════════════════════
#  [1/3] 사전 조건 점검  (check_packer_prereqs.sh 통합)
# ══════════════════════════════════════════════════════════════════
echo "========================================"
echo " [1/3] Packer 사전 조건 점검"
echo " Region : $REGION"
echo " Key    : $KEY_NAME"
echo " PEM    : $EXPANDED_KEY"
echo "========================================"

# ── 로컬 CLI 도구 ─────────────────────────────────────────────────
echo ""
echo "[ 0 ] 로컬 CLI 도구"
for cmd in packer aws; do
  if command -v "$cmd" &>/dev/null; then
    echo "  $PASS $cmd ($(command -v "$cmd"))"
  else
    echo "  $FAIL $cmd 없음 — 설치 후 재실행하세요"
    (( ERRORS++ ))
  fi
done

# ── 1. Default VPC ────────────────────────────────────────────────
echo ""
echo "[ 1 ] Default VPC"
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
  echo "  $FAIL Default VPC 없음"
  echo "       복구: aws ec2 create-default-vpc --region $REGION"
  VPC_ID=""
  (( ERRORS++ ))
else
  echo "  $PASS $VPC_ID"
fi

# ── 2. Subnets ────────────────────────────────────────────────────
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
    (( ERRORS++ ))
  else
    while IFS= read -r line; do
      echo "  $PASS $line"
    done <<< "$SUBNETS"
  fi
fi

# ── 3. Internet Gateway ───────────────────────────────────────────
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
    (( ERRORS++ ))
  else
    echo "  $PASS $IGW"
  fi
fi

# ── 4. Route Table ────────────────────────────────────────────────
echo ""
echo "[ 4 ] Route Table (0.0.0.0/0 → IGW)"
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
    (( ERRORS++ ))
  elif [ "$DEFAULT_ROUTE" != "$IGW" ]; then
    echo "  $FAIL 라우팅 IGW($DEFAULT_ROUTE) ≠ 부착된 IGW($IGW)"
    echo "       복구:"
    echo "         aws ec2 delete-route --region $REGION --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0"
    echo "         aws ec2 create-route --region $REGION --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW"
    (( ERRORS++ ))
  else
    echo "  $PASS 0.0.0.0/0 → $DEFAULT_ROUTE"
  fi
fi

# ── 5. SSH Key Pair (AWS) ─────────────────────────────────────────
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
  (( ERRORS++ ))
fi

# ── 6. PEM 파일 (로컬) ────────────────────────────────────────────
echo ""
echo "[ 6 ] PEM 파일 (로컬)"
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
  (( ERRORS++ ))
fi

echo ""
echo "========================================"
if [ "$ERRORS" -gt 0 ]; then
  echo " ❌ 사전 조건 점검 실패 ($ERRORS 건) — AMI 빌드를 중단합니다"
  echo "========================================"
  exit 1
fi
echo " ✅ 사전 조건 점검 완료 — AMI 빌드를 시작합니다"
echo "========================================"

# ══════════════════════════════════════════════════════════════════
#  [2/3] Frontend AMI 빌드  (01_k3s_frontend.sh 역할)
#         k3s v1.31.6+k3s1 바이너리 사전 설치
# ══════════════════════════════════════════════════════════════════
echo ""
echo "=============================="
echo " [2/3] Frontend AMI 빌드"
echo "       (k3s binary pre-install)"
echo "=============================="
cd "$PACKER_DIR"
packer init .

packer build \
  -only=amazon-ebs.frontend \
  -var "aws_region=$REGION" \
  -var "key_name=$KEY_NAME" \
  -var "ssh_private_key_file=$EXPANDED_KEY" \
  -var-file=variables.pkrvars.hcl \
  . 2>&1 | tee /tmp/packer-frontend.log

FRONTEND_AMI=$(grep -oE 'ami-[a-f0-9]+' /tmp/packer-frontend.log | tail -1)
echo ""
echo "  ✅ Frontend AMI: $FRONTEND_AMI"

# ══════════════════════════════════════════════════════════════════
#  [3/3] Backend AMI 빌드  (02_ceph_backend.sh + 03_beegfs_backend.sh 역할)
#         cephadm + BeeGFS 7.4.6 패키지 사전 설치
# ══════════════════════════════════════════════════════════════════
echo ""
echo "=============================="
echo " [3/3] Backend AMI 빌드"
echo "       (cephadm + BeeGFS packages pre-install)"
echo "=============================="
packer build \
  -only=amazon-ebs.backend \
  -var "aws_region=$REGION" \
  -var "key_name=$KEY_NAME" \
  -var "ssh_private_key_file=$EXPANDED_KEY" \
  -var-file=variables.pkrvars.hcl \
  . 2>&1 | tee /tmp/packer-backend.log

BACKEND_AMI=$(grep -oE 'ami-[a-f0-9]+' /tmp/packer-backend.log | tail -1)
echo ""
echo "  ✅ Backend AMI:  $BACKEND_AMI"

# ══════════════════════════════════════════════════════════════════
#  결과 요약
# ══════════════════════════════════════════════════════════════════
echo ""
echo "========================================"
echo " AMI 빌드 완료"
echo "========================================"
echo "  Frontend AMI : $FRONTEND_AMI"
echo "  Backend AMI  : $BACKEND_AMI"
echo ""
echo "  opentofu/terraform.tfvars 에 AMI ID 를 반영하세요:"
echo "    frontend_ami = \"$FRONTEND_AMI\""
echo "    backend_ami  = \"$BACKEND_AMI\""
echo ""
echo "  이후 start.sh 실행 시 Packer AMI를 사용하려면:"
echo "    USE_PACKER_AMI=true bash start.sh"
echo "========================================"
