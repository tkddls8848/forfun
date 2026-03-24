#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"

# ── 사전 패키지 체크 ──────────────────────────────────────
echo "=============================="
echo " [0/5] 사전 요구사항 확인"
echo "=============================="
MISSING=()
for cmd in tofu jq ssh scp aws kubectl helm; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING+=("$cmd")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "❌ 누락된 패키지: ${MISSING[*]}"
  echo ""
  echo "설치 방법 (Ubuntu/Debian):"
  for cmd in "${MISSING[@]}"; do
    case "$cmd" in
      tofu)    echo "  tofu   : https://opentofu.org/docs/intro/install/" ;;
      jq)      echo "  jq     : sudo apt-get install -y jq" ;;
      ssh|scp) echo "  ssh/scp: sudo apt-get install -y openssh-client" ;;
      aws)     echo "  aws    : curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o /tmp/awscliv2.zip && unzip /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install" ;;
      kubectl) echo "  kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/" ;;
      helm)    echo "  helm   : curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash" ;;
    esac
  done
  exit 1
fi
echo "✅ 모든 필수 패키지 확인 완료"
echo ""
# ─────────────────────────────────────────────────────────

echo "=============================="
echo " [1/5] AWS 인프라 생성"
echo "=============================="
cd opentofu/
tofu init
tofu apply -auto-approve
cd ..

echo "=============================="
echo " [2/5] 호스트 설정"
echo "=============================="
# EC2 인스턴스 네트워크 초기화 대기 (SSH 포트 오픈 최소 시간)
echo "  EC2 인스턴스 부팅 대기 (60초)..."
sleep 60
bash scripts/00_hosts_setup.sh

echo "=============================="
echo " [3/5] K8s 클러스터 구성"
echo "=============================="
bash scripts/01_k8s_install.sh
