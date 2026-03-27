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
N1_IP=$(tofu output -json nsd_private_ips | jq -r '.[0]')
N2_IP=$(tofu output -json nsd_private_ips | jq -r '.[1]')
cd "$SCRIPT_DIR"

echo "  Bastion : $BASTION_IP"
echo "  Master  : $MASTER_IP"
echo "  Workers : ${WORKER_IPS[*]}"
echo "  NSD     : $N1_IP  $N2_IP"

echo "=============================="
echo " [2/4] Bastion 환경 준비"
echo "=============================="
# scripts 전송
ssh $SSH_OPTS ubuntu@$BASTION_IP "rm -rf ~/scripts && mkdir -p ~/scripts"
scp -O $SSH_OPTS -r "$SCRIPT_DIR/scripts" ubuntu@$BASTION_IP:~/

# .env 생성 (프라이빗 IP 사용 — 배스천에서 직접 접근 가능)
printf "SSH_KEY=~/.ssh/storage-lab.pem
M1_PUB=%s
M1_PRIV=%s
WORKER_PUBS=(%s)
WORKER_PRIVS=(%s)
N1_PUB=%s; N2_PUB=%s
N1_PRIV=%s; N2_PRIV=%s
" \
  "$MASTER_IP" "$MASTER_IP" \
  "${WORKER_IPS[*]}" "${WORKER_IPS[*]}" \
  "$N1_IP" "$N2_IP" \
  "$N1_IP" "$N2_IP" \
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
  "export KUBECONFIG=~/.kube/config-k8s-storage-lab && cd ~ && bash scripts/install/01_ceph_install.sh"

echo "=============================="
echo " [4/4] 안내"
echo "=============================="
echo ""
echo "⚠️  GPFS는 IBM 패키지 수동 다운로드 후 진행 필요:"
echo "   1. ./gpfs-packages/ 에 .deb 파일 배치"
echo "   2. ansible-playbook -i ansible/inventory/ ansible/playbooks/gpfs.yml"
echo "   3. bash scripts/install/02_nsd_setup.sh"
echo "   4. bash scripts/install/03_csi_gpfs.sh"
echo "   5. kubectl apply -f manifests/test-pvc/"
echo ""
echo "✅ 인프라, K8s, Ceph(rook) 구성 완료!"
echo "   StorageClass: ceph-rbd, ceph-cephfs"
echo "   kubeconfig  : ~/.kube/config-k8s-storage-lab (배스천)"
echo ""
echo "   rook-ceph만 재설치 필요 시:"
echo "   bash destroy_ceph.sh && bash start_ceph.sh"
