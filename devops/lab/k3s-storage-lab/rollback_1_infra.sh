#!/bin/bash
# Rollback Stage 1: AWS 인프라 전체 삭제 (tofu destroy) + lab.env 삭제
# 전제: rollback_3_beegfs.sh, rollback_2_ceph.sh 실행 후 (소프트웨어 먼저 정리)
# 실행 순서: rollback_3_beegfs.sh → rollback_2_ceph.sh → rollback_1_infra.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ENV="$SCRIPT_DIR/lab.env"

echo "=============================="
echo " [1/1] AWS 인프라 삭제 (tofu destroy)"
echo "=============================="
echo "⚠️  EC2 인스턴스, EBS 볼륨, VPC, Security Group 이 모두 삭제됩니다."
echo ""

# 비대화 모드가 아닐 때만 확인 프롬프트 표시
if [ -t 0 ]; then
  read -r -p "계속하려면 'yes' 를 입력하세요: " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "취소됨."
    exit 0
  fi
fi

cd "$SCRIPT_DIR/opentofu"
tofu destroy -auto-approve

if [ -f "$LAB_ENV" ]; then
  rm -f "$LAB_ENV"
  echo "  lab.env 삭제 완료"
fi

echo ""
echo "✅ Stage 1 롤백 완료 — 모든 AWS 리소스 삭제됨"
