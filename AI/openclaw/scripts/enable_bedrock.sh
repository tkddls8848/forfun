#!/usr/bin/env bash
# OpenClaw — Bedrock 연동 활성화
# EC2 Instance Profile(IAM Role)로 자격증명이 자동 주입되므로
# 인스턴스 내부에서 AWS CLI / SDK는 별도 키 없이 Bedrock 호출 가능
# 이 스크립트는 OpenClaw .env에 Bedrock 리전 설정만 추가함
set -euo pipefail

cd "$(dirname "$0")/../opentofu"

PUBLIC_IP=$(tofu output -raw public_ip 2>/dev/null)
if [[ -z "$PUBLIC_IP" ]]; then
  echo "❌ 배포된 인스턴스가 없습니다. 'make apply'를 먼저 실행하세요."
  exit 1
fi

KEY_NAME=$(tofu output -json | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('ssh_command',{}).get('value',''))" \
  | grep -oP '(?<=-i ~/.ssh/)[^ ]+' || echo "")

echo "==> Bedrock 리전 설정 ($PUBLIC_IP)"
ssh -o StrictHostKeyChecking=no ubuntu@"$PUBLIC_IP" bash << 'EOF'
  ENV_FILE="$HOME/.openclaw/.env"
  mkdir -p "$(dirname "$ENV_FILE")"

  # 기존 BEDROCK/AWS 리전 설정 제거 후 추가
  grep -v '^BEDROCK_AWS_REGION\|^AWS_REGION' "$ENV_FILE" > /tmp/.env.tmp 2>/dev/null || true
  cat >> /tmp/.env.tmp << 'ENVEOF'
# Bedrock은 EC2 Instance Profile(IAM Role)로 인증 → 별도 키 불필요
# 서울 리전(ap-northeast-2)에서 Claude 모델 직접 지원 (2024년부터)
BEDROCK_AWS_REGION=ap-northeast-2
AWS_REGION=ap-northeast-2
ENVEOF
  mv /tmp/.env.tmp "$ENV_FILE"

  # OpenClaw 재시작
  if systemctl is-active --quiet openclaw 2>/dev/null; then
    sudo systemctl restart openclaw
    echo "✅ openclaw 서비스 재시작 완료"
  elif docker ps --format '{{.Names}}' | grep -q openclaw; then
    docker restart openclaw
    echo "✅ openclaw 컨테이너 재시작 완료"
  else
    echo "ℹ️  OpenClaw 프로세스를 찾을 수 없습니다. 수동으로 재시작하세요."
  fi
EOF

echo ""
echo "✅ Bedrock 설정 완료"
echo "   UI: http://$PUBLIC_IP:18789"
