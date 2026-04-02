#!/bin/bash
# k3s-storage-lab 전체 구성 자동화 (Phase 1~5)
# USE_PACKER_AMI=true: Packer 사전 빌드 AMI 사용 (패키지 설치 단계 스킵)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"
USE_PACKER_AMI=${USE_PACKER_AMI:-false}

echo "=============================="
echo " [0/5] 사전 요구사항 확인"
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
echo " [1/5] AWS 인프라 생성"
echo "=============================="
cd "$SCRIPT_DIR/opentofu"
tofu init
tofu apply -auto-approve

FRONTEND_IP=$(tofu output -raw frontend_public_ip)
BACKEND_IP=$(tofu output -raw backend_public_ip)
BACKEND_PRIVATE_IP=$(tofu output -raw backend_private_ip)
echo "  Frontend Public IP  : $FRONTEND_IP"
echo "  Backend Public IP   : $BACKEND_IP"
echo "  Backend Private IP  : $BACKEND_PRIVATE_IP"

echo "=============================="
echo " [2/5] SSH 연결 대기"
echo "=============================="
for IP in $FRONTEND_IP $BACKEND_IP; do
  echo -n "  $IP 대기 중..."
  until ssh $SSH_OPTS ubuntu@$IP "echo ok" &>/dev/null; do
    echo -n "."; sleep 5
  done
  echo " ✓"
done

echo "=============================="
echo " [3/5] Phase 2: k3s Frontend 구성"
echo "=============================="
if [ "$USE_PACKER_AMI" = "true" ]; then
  echo "  [Packer AMI] 서비스 등록/조인만 실행"
  ssh $SSH_OPTS ubuntu@$FRONTEND_IP 'sudo bash -s' < "$SCRIPT_DIR/scripts/01_k3s_frontend_join.sh"
else
  ssh $SSH_OPTS ubuntu@$FRONTEND_IP 'sudo bash -s' < "$SCRIPT_DIR/scripts/01_k3s_frontend.sh"
fi

echo "=============================="
echo " [4/5] Phase 3+4: Backend 구성 (Ceph + BeeGFS)"
echo "=============================="
if [ "$USE_PACKER_AMI" = "true" ]; then
  echo "  [Packer AMI] bootstrap/conf만 실행"
  ssh $SSH_OPTS ubuntu@$BACKEND_IP 'sudo bash -s' < "$SCRIPT_DIR/scripts/02_ceph_bootstrap_only.sh"
  ssh $SSH_OPTS ubuntu@$BACKEND_IP 'sudo bash -s' < "$SCRIPT_DIR/scripts/03_beegfs_conf_only.sh"
else
  ssh $SSH_OPTS ubuntu@$BACKEND_IP 'sudo bash -s' < "$SCRIPT_DIR/scripts/02_ceph_backend.sh"
  ssh $SSH_OPTS ubuntu@$BACKEND_IP 'sudo bash -s' < "$SCRIPT_DIR/scripts/03_beegfs_backend.sh"
fi

# Ceph 정보 수집
CEPH_FSID=$(ssh $SSH_OPTS ubuntu@$BACKEND_IP "sudo cephadm shell -- ceph fsid 2>/dev/null" | tr -d '\r\n')
CEPH_ADMIN_KEY=$(ssh $SSH_OPTS ubuntu@$BACKEND_IP "sudo cephadm shell -- ceph auth get-key client.admin 2>/dev/null" | tr -d '\r\n')

# RBD pool 생성 (rbd pool init은 CSI가 첫 볼륨 생성 시 자동 처리 — hang 방지를 위해 생략)
ssh $SSH_OPTS ubuntu@$BACKEND_IP \
  "sudo cephadm shell -- ceph osd pool create kubernetes 2>/dev/null || true"

echo "=============================="
echo " [5/5] Phase 5: CSI 연동"
echo "=============================="
# 매니페스트 전송
scp -O $SSH_OPTS -r "$SCRIPT_DIR/manifests" ubuntu@$FRONTEND_IP:~/
scp -O $SSH_OPTS "$SCRIPT_DIR/scripts/04_csi_install.sh" ubuntu@$FRONTEND_IP:~/

ssh $SSH_OPTS ubuntu@$FRONTEND_IP \
  "BACKEND_PRIVATE_IP='$BACKEND_PRIVATE_IP' \
   CEPH_FSID='$CEPH_FSID' \
   CEPH_ADMIN_KEY='$CEPH_ADMIN_KEY' \
   SCRIPT_DIR=\$HOME \
   bash ~/04_csi_install.sh"

echo ""
echo "✅ k3s-storage-lab 구성 완료"
echo ""
echo "  Frontend   : ssh -i $SSH_KEY ubuntu@$FRONTEND_IP"
echo "  Backend    : ssh -i $SSH_KEY ubuntu@$BACKEND_IP"
echo ""
echo "  다음 단계:"
echo "    ssh -i $SSH_KEY ubuntu@$FRONTEND_IP"
echo "    bash scripts/05_verify.sh"
