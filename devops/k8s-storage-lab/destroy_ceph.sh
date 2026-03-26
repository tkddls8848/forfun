#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [1/3] 인프라 정보 수집"
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

echo "=============================="
echo " [2/3] Bastion 환경 준비"
echo "=============================="
# .env 생성 (start_ceph.sh와 동일)
ssh $SSH_OPTS ubuntu@$BASTION_IP "mkdir -p ~/scripts"
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

# kubectl 설치 (없는 경우)
ssh $SSH_OPTS ubuntu@$BASTION_IP "
  if ! command -v kubectl &>/dev/null; then
    curl -sLO https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
  fi
"

echo "=============================="
echo " [3/3] rook-ceph 삭제 (Bastion에서 실행)"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP << 'REMOTE'
set -e
export KUBECONFIG=~/.kube/config-k8s-storage-lab
source ~/scripts/.env
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"
WORKER_COUNT=${#WORKER_PUBS[@]}

echo "=============================="
echo " [1/5] API 서버 연결 확인"
echo "=============================="
API_OK=false
if kubectl cluster-info --request-timeout=10s &>/dev/null; then
  echo "  ✅ API 서버 응답 확인"
  API_OK=true
else
  echo "  ⚠️  API 서버 응답 없음 - K8s 리소스 삭제 단계 스킵"
fi

echo "=============================="
echo " [2/5] StorageClass 삭제"
echo "=============================="
if $API_OK; then
  kubectl delete storageclass ceph-rbd ceph-cephfs --ignore-not-found
  echo "  ✅ StorageClass 삭제 완료"
else
  echo "  스킵 (API 서버 미응답)"
fi

echo "=============================="
echo " [3/5] CephFilesystem / CephBlockPool 삭제"
echo "=============================="
if $API_OK; then
  kubectl -n rook-ceph delete cephfilesystem labfs --ignore-not-found
  kubectl -n rook-ceph delete cephblockpool replicapool --ignore-not-found
  echo "  [대기] CephFilesystem/BlockPool 삭제 대기 (30s)..."
  sleep 30
  echo "  ✅ CephFilesystem/BlockPool 삭제 완료"
else
  echo "  스킵 (API 서버 미응답)"
fi

echo "=============================="
echo " [4/5] CephCluster 삭제 (finalizer 강제 제거)"
echo "=============================="
if $API_OK; then
  kubectl -n rook-ceph patch cephcluster rook-ceph \
    --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  kubectl -n rook-ceph delete cephcluster rook-ceph --ignore-not-found
  echo "  [대기] CephCluster 삭제 대기 (30s)..."
  sleep 30

  $CSSH$M1_PUB "helm uninstall rook-ceph -n rook-ceph 2>/dev/null || true"
  kubectl delete namespace rook-ceph --ignore-not-found
  echo "  [대기] namespace 삭제 대기 (20s)..."
  sleep 20

  kubectl get crd | grep ceph | awk '{print $1}' | xargs kubectl delete crd --ignore-not-found 2>/dev/null || true
  echo "  ✅ CephCluster / namespace / CRD 삭제 완료"
else
  echo "  스킵 (API 서버 미응답)"
fi

echo "=============================="
echo " [5/5] 워커 노드 OSD 디스크 초기화"
echo "=============================="
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  NODE_IP="${WORKER_PUBS[$i]}"
  NODE_NAME="worker-$((i + 1))"
  echo "  $NODE_NAME ($NODE_IP) 디스크 초기화 중..."
  $CSSH$NODE_IP "
    for dev in /dev/xvd{b,c} /dev/nvme{1,2}n1; do
      [ -b \"\$dev\" ] || continue
      echo \"  wipe: \$dev\"
      sudo sgdisk --zap-all \"\$dev\" 2>/dev/null || true
      sudo dd if=/dev/zero of=\"\$dev\" bs=1M count=100 2>/dev/null || true
    done
    sudo dmsetup remove_all 2>/dev/null || true
    sudo pvremove -ff /dev/xvd{b,c} 2>/dev/null || true
    sudo rm -rf /var/lib/rook
    echo '  ✅ 디스크 초기화 완료'
  "
done

echo ""
echo "✅ rook-ceph 삭제 완료"
echo "   재설치: bash start_ceph.sh"
REMOTE
