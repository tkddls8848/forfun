#!/usr/bin/env bash
# OpenClaw 게이트웨이 토큰 확인
set -euo pipefail

cd "$(dirname "$0")/../opentofu"
PUBLIC_IP=$(tofu output -raw public_ip 2>/dev/null)

if [[ -z "$PUBLIC_IP" ]]; then
  echo "❌ 배포된 인스턴스가 없습니다. 'make apply'를 먼저 실행하세요."
  exit 1
fi

echo "==> OpenClaw 게이트웨이 토큰 ($PUBLIC_IP)"
ssh -o StrictHostKeyChecking=no ubuntu@"$PUBLIC_IP" \
  "grep -i 'token\|gateway' ~/.openclaw/.env 2>/dev/null || echo '설치 진행 중일 수 있습니다. 잠시 후 재시도하세요.'"
