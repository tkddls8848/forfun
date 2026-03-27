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
echo "  NSD-1   : $N1_IP"
echo "  NSD-2   : $N2_IP"

echo "=============================="
echo " [2/3] Bastion 환경 준비"
echo "=============================="
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

echo "=============================="
echo " [3/3] GPFS 삭제 (Bastion에서 실행)"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP << 'REMOTE'
set -e
export KUBECONFIG=~/.kube/config-k8s-storage-lab
source ~/scripts/.env
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"
WORKER_COUNT=${#WORKER_PUBS[@]}
ALL_GPFS_IPS=($M1_PUB ${WORKER_PUBS[@]} $N1_PUB $N2_PUB)

echo "=============================="
echo " [1/6] API 서버 연결 확인"
echo "=============================="
API_OK=false
if kubectl cluster-info --request-timeout=10s &>/dev/null; then
  echo "  ✅ API 서버 응답 확인"
  API_OK=true
else
  echo "  ⚠️  API 서버 응답 없음 - K8s 리소스 삭제 단계 스킵"
fi

echo "=============================="
echo " [2/6] GPFS StorageClass / CSI 삭제"
echo "=============================="
if $API_OK; then
  kubectl delete storageclass gpfs-scale --ignore-not-found

  $CSSH$M1_PUB "
    helm uninstall ibm-spectrum-scale-csi-operator \
      -n ibm-spectrum-scale-csi-driver 2>/dev/null || true
    kubectl delete namespace ibm-spectrum-scale-csi-driver --ignore-not-found
    kubectl delete crd \$(kubectl get crd 2>/dev/null \
      | grep spectrumscale | awk '{print \$1}') --ignore-not-found 2>/dev/null || true
    kubectl delete secret scale-secret \
      -n ibm-spectrum-scale-csi-driver --ignore-not-found 2>/dev/null || true
  " || true
  echo "  ✅ StorageClass / CSI 삭제 완료"
else
  echo "  스킵 (API 서버 미응답)"
fi

echo "=============================="
echo " [3/6] GPFS GUI 중지 (nsd-1)"
echo "=============================="
$CSSH$N1_PUB "
  sudo systemctl stop gpfsgui 2>/dev/null || \
  sudo /usr/lpp/mmfs/gui/bin/guiserver stop 2>/dev/null || true
  echo '  ✅ GUI 중지 완료'
" || true

echo "=============================="
echo " [4/6] GPFS 파일시스템 언마운트 및 삭제 (nsd-1)"
echo "=============================="
$CSSH$N1_PUB "
  MMFS_BIN=/usr/lpp/mmfs/bin

  echo '  --- 마운트 해제 ---'
  sudo \$MMFS_BIN/mmumount gpfs0 -a 2>/dev/null || true

  echo '  --- 파일시스템 삭제 ---'
  sudo \$MMFS_BIN/mmdelfs gpfs0 2>/dev/null || true

  echo '  --- NSD 삭제 ---'
  sudo \$MMFS_BIN/mmdelnsd nsd1disk nsd2disk 2>/dev/null || true

  echo '  ✅ 파일시스템 / NSD 삭제 완료'
" || true

echo "=============================="
echo " [5/6] GPFS 클러스터 해체 (전체 노드 → nsd-1)"
echo "=============================="
# 모든 노드에서 mmshutdown 후 클러스터 삭제
for ip in "${ALL_GPFS_IPS[@]}"; do
  $CSSH$ip "sudo /usr/lpp/mmfs/bin/mmshutdown 2>/dev/null || true" || true
done

$CSSH$N1_PUB "
  sudo /usr/lpp/mmfs/bin/mmdelnode \
    -N \$(sudo /usr/lpp/mmfs/bin/mmlscluster 2>/dev/null \
         | grep ':' | grep -v 'Cluster\|^$' \
         | awk '{print \$1}' | tr '\n' ',' | sed 's/,$//') \
    2>/dev/null || true
  sudo /usr/lpp/mmfs/bin/mmdelcluster 2>/dev/null || true
  echo '  ✅ 클러스터 해체 완료'
" || true

echo "=============================="
echo " [6/6] GPFS 패키지 제거 (전체 노드)"
echo "=============================="
for ip in "${ALL_GPFS_IPS[@]}"; do
  echo "  패키지 제거: $ip"
  $CSSH$ip "
    sudo dpkg -P gpfs.base gpfs.gpl gpfs.adv gpfs.crypto \
                 gpfs.ext gpfs.gui 2>/dev/null || true
    sudo rm -rf /usr/lpp/mmfs /tmp/gpfs-packages
    sudo rm -f /etc/modules-load.d/gpfs.conf
    echo '  ✅ 완료'
  " || true
done

echo ""
echo "✅ GPFS 삭제 완료"
echo "   재설치: ansible-playbook -i ansible/inventory/ ansible/playbooks/gpfs.yml"
REMOTE
