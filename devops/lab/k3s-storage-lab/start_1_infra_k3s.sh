#!/bin/bash
# Stage 1: AWS 인프라 생성 + k3s 설치
# 완료 후 lab.env 에 상태 저장 — Stage 2/3이 이 파일을 source 함
# 롤백: rollback_1_infra.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ENV="$SCRIPT_DIR/lab.env"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [0/3] 사전 요구사항 확인"
echo "=============================="
MISSING=()
for cmd in tofu aws ssh scp; do
  command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
[ -f "$SSH_KEY" ] || MISSING+=("ssh-key:$SSH_KEY")
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "❌ 누락된 항목: ${MISSING[*]}"
  exit 1
fi
echo "✅ 모든 필수 항목 확인 완료"

echo "=============================="
echo " [1/3] AWS 인프라 생성"
echo "=============================="
cd "$SCRIPT_DIR/opentofu"
tofu init
tofu apply -auto-approve

FRONTEND_IP=$(tofu output -raw frontend_public_ip)
BACKEND_IP=$(tofu output -raw backend_public_ip)
BACKEND_PRIVATE_IP=$(tofu output -raw backend_private_ip)
CEPH_OSD_1_VOL=$(tofu output -raw ceph_osd_1_volume_id)
CEPH_OSD_2_VOL=$(tofu output -raw ceph_osd_2_volume_id)
BEEGFS_STORAGE_1_VOL=$(tofu output -raw beegfs_storage_1_volume_id)
BEEGFS_STORAGE_2_VOL=$(tofu output -raw beegfs_storage_2_volume_id)

cat > "$LAB_ENV" <<EOF
SSH_KEY=${SSH_KEY}
FRONTEND_IP=${FRONTEND_IP}
BACKEND_IP=${BACKEND_IP}
BACKEND_PRIVATE_IP=${BACKEND_PRIVATE_IP}
CEPH_OSD_1_VOL=${CEPH_OSD_1_VOL}
CEPH_OSD_2_VOL=${CEPH_OSD_2_VOL}
BEEGFS_STORAGE_1_VOL=${BEEGFS_STORAGE_1_VOL}
BEEGFS_STORAGE_2_VOL=${BEEGFS_STORAGE_2_VOL}
EOF
echo "  상태 저장 완료: $LAB_ENV"
echo "  Frontend Public IP  : $FRONTEND_IP"
echo "  Backend Public IP   : $BACKEND_IP"
echo "  Ceph OSD volumes    : $CEPH_OSD_1_VOL, $CEPH_OSD_2_VOL"
echo "  BeeGFS volumes      : $BEEGFS_STORAGE_1_VOL, $BEEGFS_STORAGE_2_VOL"

echo "=============================="
echo " [2/3] SSH 연결 대기"
echo "=============================="
for IP in $FRONTEND_IP $BACKEND_IP; do
  echo -n "  $IP 대기 중..."
  until ssh $SSH_OPTS ec2-user@$IP "echo ok" &>/dev/null; do
    echo -n "."; sleep 5
  done
  echo " ✓"
done

echo "=============================="
echo " [3/3] k3s Frontend 구성"
echo "=============================="
ssh $SSH_OPTS ec2-user@$FRONTEND_IP 'sudo bash -s' < "$SCRIPT_DIR/scripts/01_k3s_frontend.sh"
scp -O $SSH_OPTS -r "$SCRIPT_DIR/manifests" ec2-user@$FRONTEND_IP:~/

cat > "$SCRIPT_DIR/ADDRESS.md" <<EOF
# k3s-storage-lab 접속 정보

## Frontend (k3s server)
\`\`\`
ssh -i /home/psi/.ssh/storage-lab.pem -o StrictHostKeyChecking=no ec2-user@${FRONTEND_IP}
\`\`\`

## Backend (Ceph + BeeGFS)
\`\`\`
ssh -i /home/psi/.ssh/storage-lab.pem -o StrictHostKeyChecking=no ec2-user@${BACKEND_IP}
\`\`\`
EOF
echo "  접속 정보 저장 완료: $SCRIPT_DIR/ADDRESS.md"

echo ""
echo "✅ Stage 1 완료 — 인프라 + k3s 구성됨"
echo "  다음 단계: bash start_2_ceph.sh"
