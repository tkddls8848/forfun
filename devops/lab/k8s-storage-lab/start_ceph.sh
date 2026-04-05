#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [0/4] 사전 요구사항 확인"
echo "=============================="
MISSING=()
for cmd in tofu jq ssh scp; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING+=("$cmd")
  fi
done
if [ ! -f "$SSH_KEY" ]; then
  MISSING+=("ssh-key:$SSH_KEY")
fi
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "❌ 누락된 항목: ${MISSING[*]}"
  exit 1
fi
echo "✅ 모든 필수 항목 확인 완료"

echo "=============================="
echo " [1/4] 인프라 정보 수집"
echo "=============================="
cd "$SCRIPT_DIR/opentofu"
BASTION_IP=$(tofu output -raw bastion_public_ip)
MASTER_IP=$(tofu output -json master_private_ips | jq -r '.[0]')
WORKER_IPS=($(tofu output -json worker_private_ips | jq -r '.[]'))
cd "$SCRIPT_DIR"

echo "  Bastion : $BASTION_IP"
echo "  Master  : $MASTER_IP"
echo "  Workers : ${WORKER_IPS[*]}"

echo "=============================="
echo " [2/4] Bastion 환경 준비"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP "rm -rf ~/scripts && mkdir -p ~/scripts"
scp -O $SSH_OPTS -r "$SCRIPT_DIR/scripts" ubuntu@$BASTION_IP:~/

# .env 생성 (배스천에서 scripts/ceph_install.sh가 참조)
printf "SSH_KEY=\$HOME/.ssh/storage-lab.pem
M1_PUB=%s
M1_PRIV=%s
WORKER_PUBS=(%s)
WORKER_PRIVS=(%s)
" \
  "$MASTER_IP" "$MASTER_IP" \
  "${WORKER_IPS[*]}" "${WORKER_IPS[*]}" \
  | ssh $SSH_OPTS ubuntu@$BASTION_IP "cat > ~/scripts/.env"

# kubectl 설치 (배스천에 없는 경우)
ssh $SSH_OPTS ubuntu@$BASTION_IP "
  if ! command -v kubectl &>/dev/null; then
    echo '  kubectl 설치 중...'
    curl -sLO https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
    echo '  ✅ kubectl 설치 완료'
  else
    echo '  ✅ kubectl 이미 설치됨'
  fi
"

echo "=============================="
echo " [3/4] Ceph 클러스터 구성 (Bastion에서 실행)"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "export KUBECONFIG=~/.kube/config-k8s-storage-lab && cd ~ && bash scripts/ceph_install.sh"

echo "=============================="
echo " [4/4] 안내"
echo "=============================="
echo ""
echo "✅ 인프라, K8s, Ceph(rook) 구성 완료!"
echo "   StorageClass: ceph-rbd, ceph-cephfs"
echo "   kubeconfig  : ~/.kube/config-k8s-storage-lab (배스천)"
echo ""
echo "⚠️  BeeGFS 설치는 별도 실행 필요:"
echo "   1. bash start_beegfs.sh"
echo "   2. kubectl apply -f manifests/examples/test-pvc-beegfs.yaml"
echo ""
echo "   rook-ceph만 재설치 필요 시:"
echo "   bash destroy_ceph.sh && bash start_ceph.sh"
