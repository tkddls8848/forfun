#!/bin/bash
# 00_build_ami.sh ??Packer ?¬ì „ ì¡°ê±´ ?ê? + bastion/master/worker AMI ë¹Œë“œ
# ?¤í–‰: bash scripts/provision/00_build_ami.sh [REGION] [KEY_NAME] [PEM_FILE]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKER_DIR="$LAB_DIR/packer"

REGION="${1:-ap-northeast-2}"
KEY_NAME="${2:-storage-lab}"
KEY_FILE="${3:-${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}}"
EXPANDED_KEY="${KEY_FILE/#\~/$HOME}"

# Packer ?„ì‹œ ë³´ì•ˆ ê·¸ë£¹ ?•ë¦¬ (ë¹Œë“œ ?±ê³µ/?¤íŒ¨ ëª¨ë‘ ?¤í–‰)
cleanup_packer_sgs() {
  echo ""
  echo "========================================"
  echo " [cleanup] Packer ?„ì‹œ ë³´ì•ˆ ê·¸ë£¹ ?•ë¦¬"
  echo "========================================"
  local sgs
  sgs=$(aws ec2 describe-security-groups --region "$REGION" \
    --filters "Name=group-name,Values=packer_*" \
    --query 'SecurityGroups[*].GroupId' --output text 2>/dev/null)
  if [ -z "$sgs" ] || [ "$sgs" = "None" ]; then
    echo "  ?”ì—¬ ë³´ì•ˆ ê·¸ë£¹ ?†ìŒ"
    return
  fi
  for sg in $sgs; do
    if aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>/dev/null; then
      echo "  ?? œ: $sg"
    else
      echo "  ê±´ë„ˆ?€ (?¬ìš© ì¤?: $sg"
    fi
  done
}
trap cleanup_packer_sgs EXIT

PASS="[PASS]"
FAIL="[FAIL]"
WARN="[WARN]"
ERRORS=0

# ?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•
#  [1/4] ?¬ì „ ì¡°ê±´ ?ê?
# ?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•
echo "========================================"
echo " [1/4] Packer ?¬ì „ ì¡°ê±´ ?ê?"
echo " Region : $REGION"
echo " Key    : $KEY_NAME"
echo " PEM    : $EXPANDED_KEY"
echo "========================================"

# ?€?€ ë¡œì»¬ CLI ?„êµ¬ ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
echo ""
echo "[ 0 ] ë¡œì»¬ CLI ?„êµ¬"
for cmd in packer aws; do
  if command -v "$cmd" &>/dev/null; then
    echo "  $PASS $cmd ($(command -v "$cmd"))"
  else
    echo "  $FAIL $cmd ?†ìŒ ???¤ì¹˜ ???¬ì‹¤?‰í•˜?¸ìš”"
    (( ERRORS++ ))
  fi
done

# ?€?€ 1. Default VPC ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
echo ""
echo "[ 1 ] Default VPC"
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
  echo "  $FAIL Default VPC ?†ìŒ"
  echo "       ë³µêµ¬: aws ec2 create-default-vpc --region $REGION"
  VPC_ID=""
  (( ERRORS++ ))
else
  echo "  $PASS $VPC_ID"
fi

# ?€?€ 2. Subnets ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
echo ""
echo "[ 2 ] Subnets (Default VPC)"
if [ -z "$VPC_ID" ]; then
  echo "  $WARN VPC ?†ìœ¼ë¯€ë¡??œë¸Œ??ê²€???ëµ"
else
  SUBNETS=$(aws ec2 describe-subnets --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[*].{ID:SubnetId,AZ:AvailabilityZone}' \
    --output text 2>/dev/null)
  if [ -z "$SUBNETS" ]; then
    echo "  $FAIL ?œë¸Œ???†ìŒ"
    echo "       ë³µêµ¬ ?ˆì‹œ:"
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

# ?€?€ 3. Internet Gateway ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
echo ""
echo "[ 3 ] Internet Gateway"
if [ -z "$VPC_ID" ]; then
  echo "  $WARN VPC ?†ìœ¼ë¯€ë¡?IGW ê²€???ëµ"
else
  IGW=$(aws ec2 describe-internet-gateways --region "$REGION" \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null)
  if [ "$IGW" = "None" ] || [ -z "$IGW" ]; then
    echo "  $FAIL IGW ?†ìŒ"
    echo "       ë³µêµ¬:"
    echo "         IGW_ID=\$(aws ec2 create-internet-gateway --region $REGION --query 'InternetGateway.InternetGatewayId' --output text)"
    echo "         aws ec2 attach-internet-gateway --region $REGION --internet-gateway-id \$IGW_ID --vpc-id $VPC_ID"
    (( ERRORS++ ))
  else
    echo "  $PASS $IGW"
  fi
fi

# ?€?€ 4. Route Table ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
echo ""
echo "[ 4 ] Route Table (0.0.0.0/0 ??IGW)"
if [ -z "$VPC_ID" ]; then
  echo "  $WARN VPC ?†ìœ¼ë¯€ë¡??¼ìš°??ê²€???ëµ"
else
  RT_ID=$(aws ec2 describe-route-tables --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
    --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null)
  DEFAULT_ROUTE=$(aws ec2 describe-route-tables --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "RouteTables[*].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId" \
    --output text 2>/dev/null)

  if ! echo "$DEFAULT_ROUTE" | grep -q "igw-"; then
    echo "  $FAIL ê¸°ë³¸ ê²½ë¡œ(0.0.0.0/0) ?†ìŒ"
    echo "       ë³µêµ¬: aws ec2 create-route --region $REGION --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW"
    (( ERRORS++ ))
  elif [ "$DEFAULT_ROUTE" != "$IGW" ]; then
    echo "  $FAIL ?¼ìš°??IGW($DEFAULT_ROUTE) ??ë¶€ì°©ëœ IGW($IGW)"
    echo "       ë³µêµ¬:"
    echo "         aws ec2 delete-route --region $REGION --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0"
    echo "         aws ec2 create-route --region $REGION --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW"
    (( ERRORS++ ))
  else
    echo "  $PASS 0.0.0.0/0 ??$DEFAULT_ROUTE"
  fi
fi

# ?€?€ 5. SSH Key Pair (AWS) ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
echo ""
echo "[ 5 ] SSH Key Pair (AWS EC2)"
KEY_EXISTS=$(aws ec2 describe-key-pairs --region "$REGION" \
  --key-names "$KEY_NAME" \
  --query 'KeyPairs[0].KeyName' --output text 2>/dev/null)
if [ "$KEY_EXISTS" = "$KEY_NAME" ]; then
  echo "  $PASS $KEY_NAME"
else
  echo "  $FAIL Key Pair '$KEY_NAME' ê°€ AWS???†ìŒ"
  echo "       EC2 ì½˜ì†” ?ëŠ” CLIë¡????˜ì–´ë¥??ì„±/?±ë¡?˜ì„¸??
  (( ERRORS++ ))
fi

# ?€?€ 6. PEM ?Œì¼ (ë¡œì»¬) ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€
echo ""
echo "[ 6 ] PEM ?Œì¼ (ë¡œì»¬)"
if [ -f "$EXPANDED_KEY" ]; then
  PERMS=$(stat -c "%a" "$EXPANDED_KEY" 2>/dev/null)
  if [ "$PERMS" = "400" ] || [ "$PERMS" = "600" ]; then
    echo "  $PASS $EXPANDED_KEY (ê¶Œí•œ: $PERMS)"
  else
    echo "  $WARN $EXPANDED_KEY ì¡´ì¬?˜ì?ë§?ê¶Œí•œ??$PERMS (400 ê¶Œì¥)"
    echo "       ë³µêµ¬: chmod 400 $EXPANDED_KEY"
  fi
else
  echo "  $FAIL $EXPANDED_KEY ?†ìŒ"
  echo "       AWS?ì„œ ???˜ì–´ ?¤ìš´ë¡œë“œ ??~/.ssh/ ??ë°°ì¹˜?˜ì„¸??
  (( ERRORS++ ))
fi

echo ""
echo "========================================"
if [ "$ERRORS" -gt 0 ]; then
  echo " ???¬ì „ ì¡°ê±´ ?ê? ?¤íŒ¨ ($ERRORS ê±? ??AMI ë¹Œë“œë¥?ì¤‘ë‹¨?©ë‹ˆ??
  echo "========================================"
  exit 1
fi
echo " ???¬ì „ ì¡°ê±´ ?ê? ?„ë£Œ ??AMI ë¹Œë“œë¥??œì‘?©ë‹ˆ??
echo "========================================"

cd "$PACKER_DIR"
packer init .

# ?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•
#  [2/4] Bastion AMI ë¹Œë“œ
#         ansible-core + boto3 + collections ?¬ì „ ?¤ì¹˜
# ?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•
echo ""
echo "=============================="
echo " [2/4] Bastion AMI ë¹Œë“œ"
echo "       (ansible-core + boto3 + collections)"
echo "=============================="
packer build \
  -only=amazon-ebs.bastion \
  -var "aws_region=$REGION" \
  -var "key_name=$KEY_NAME" \
  -var "ssh_private_key_file=$EXPANDED_KEY" \
  -var-file=variables.pkrvars.hcl \
  . 2>&1 | tee /tmp/packer-bastion.log

BASTION_AMI=$(grep -oE 'ami-[a-f0-9]+' /tmp/packer-bastion.log | tail -1)
echo ""
echo "  ??Bastion AMI: $BASTION_AMI"

# ?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•
#  [3/4] Master AMI ë¹Œë“œ
#         containerd + kubeadm/kubelet/kubectl ?¬ì „ ?¤ì¹˜
# ?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•
echo ""
echo "=============================="
echo " [3/4] Master AMI ë¹Œë“œ"
echo "       (containerd + kubeadm/kubelet/kubectl 1.31)"
echo "=============================="
packer build \
  -only=amazon-ebs.master \
  -var "aws_region=$REGION" \
  -var "key_name=$KEY_NAME" \
  -var "ssh_private_key_file=$EXPANDED_KEY" \
  -var-file=variables.pkrvars.hcl \
  . 2>&1 | tee /tmp/packer-master.log

MASTER_AMI=$(grep -oE 'ami-[a-f0-9]+' /tmp/packer-master.log | tail -1)
echo ""
echo "  ??Master AMI: $MASTER_AMI"

# ?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•
#  [4/4] Worker AMI ë¹Œë“œ
#         containerd + kubeadm/kubelet/kubectl + ì»¤ë„ 6.8 + BeeGFS 7.4.6 ëª¨ë“ˆ
# ?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•
echo ""
echo "=============================="
echo " [4/4] Worker AMI ë¹Œë“œ"
echo "       (containerd + kubeadm + kernel 6.8 + BeeGFS 7.4.6 module)"
echo "=============================="
packer build \
  -only=amazon-ebs.worker \
  -var "aws_region=$REGION" \
  -var "key_name=$KEY_NAME" \
  -var "ssh_private_key_file=$EXPANDED_KEY" \
  -var-file=variables.pkrvars.hcl \
  . 2>&1 | tee /tmp/packer-worker.log

WORKER_AMI=$(grep -oE 'ami-[a-f0-9]+' /tmp/packer-worker.log | tail -1)
echo ""
echo "  ??Worker AMI: $WORKER_AMI"

# ?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•
#  ê²°ê³¼ ?”ì•½
# ?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•?â•
echo ""
echo "========================================"
echo " AMI ë¹Œë“œ ?„ë£Œ"
echo "========================================"
echo "  Bastion AMI : $BASTION_AMI"
echo "  Master AMI  : $MASTER_AMI"
echo "  Worker AMI  : $WORKER_AMI"
echo ""
echo "  opentofu/terraform.tfvars ??AMI ID ë¥?ë°˜ì˜?˜ì„¸??"
echo "    ami_bastion = \"$BASTION_AMI\""
echo "    ami_master  = \"$MASTER_AMI\""
echo "    ami_worker  = \"$WORKER_AMI\""
echo ""
echo "  ?´í›„ start_k8s.sh ?¤í–‰ ??Packer AMIë¥??¬ìš©?˜ë ¤ë©?"
echo "    USE_PACKER_AMI=true bash scripts/lifecycle/start_k8s.sh"
echo "========================================"
