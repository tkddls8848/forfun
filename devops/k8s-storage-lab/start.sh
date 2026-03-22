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
sleep 30
bash scripts/00_hosts_setup.sh

echo "=============================="
echo " [3/5] K8s 클러스터 구성"
echo "=============================="
bash scripts/04_k8s_install.sh

echo "=============================="
echo " [4/5] Ceph 클러스터 구성 (rook-ceph)"
echo "=============================="
bash scripts/01_ceph_install.sh

echo "=============================="
echo " [5/5] 안내"
echo "=============================="
echo ""
echo "⚠️  GPFS는 IBM 패키지 수동 다운로드 후 진행 필요:"
echo "   1. ./gpfs-packages/ 에 .deb 파일 배치"
echo "   2. bash scripts/02_gpfs_install.sh"
echo "   3. bash scripts/03_nsd_setup.sh"
echo "   4. bash scripts/06_csi_gpfs.sh"
echo "   5. bash scripts/99_test_pvc.sh"
echo ""
echo "✅ 인프라, K8s, Ceph(rook) 구성 완료!"
echo "   StorageClass: ceph-rbd, ceph-cephfs"
echo "   kubeconfig  : ~/.kube/config-k8s-storage-lab"
