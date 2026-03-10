#!/usr/bin/env bash
# 서울 리전 Ubuntu 24.04 LTS 최신 AMI ID 조회
set -euo pipefail

REGION="${1:-ap-northeast-2}"

echo "==> Ubuntu 24.04 LTS 최신 AMI (리전: $REGION)"
aws ec2 describe-images \
  --region "$REGION" \
  --owners 099720109477 \
  --filters \
    'Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*' \
    'Name=state,Values=available' \
  --query 'sort_by(Images,&CreationDate)[-1].[ImageId,Name,CreationDate]' \
  --output table
