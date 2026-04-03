#!/bin/bash
# k3s-storage-lab 전체 구성 자동화 (Phase 1~5)
# 전제: 00_build_ami.sh 로 Packer AMI 가 사전 빌드되어 있어야 합니다.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

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
ssh $SSH_OPTS ubuntu@$FRONTEND_IP 'sudo bash -s' < "$SCRIPT_DIR/scripts/01_k3s_frontend.sh"

echo "=============================="
echo " [4/5] Phase 3+4: Backend 구성 (Ceph + BeeGFS)"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BACKEND_IP 'sudo bash -s' < "$SCRIPT_DIR/scripts/02_ceph_backend.sh"
ssh $SSH_OPTS ubuntu@$BACKEND_IP 'sudo bash -s' < "$SCRIPT_DIR/scripts/03_beegfs_backend.sh"

# Ceph HEALTH_OK 대기 후 정보 수집
echo "  Ceph 클러스터 HEALTH_OK 대기..."
for i in $(seq 1 24); do
  CEPH_STATUS=$(ssh $SSH_OPTS ubuntu@$BACKEND_IP \
    "sudo cephadm shell -- ceph status --format json 2>/dev/null" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['health']['status'])" 2>/dev/null || true)
  if [ "$CEPH_STATUS" = "HEALTH_OK" ] || [ "$CEPH_STATUS" = "HEALTH_WARN" ]; then
    echo "  Ceph 상태: $CEPH_STATUS ✅"
    break
  fi
  echo -n "  ($i/24) $CEPH_STATUS 대기 중..."; sleep 10
done
if [ "$CEPH_STATUS" != "HEALTH_OK" ] && [ "$CEPH_STATUS" != "HEALTH_WARN" ]; then
  echo "❌ Ceph 클러스터가 준비되지 않았습니다 (상태: $CEPH_STATUS). 백엔드 로그를 확인하세요."
  exit 1
fi

CEPH_FSID=$(ssh $SSH_OPTS ubuntu@$BACKEND_IP "sudo cephadm shell -- ceph fsid 2>/dev/null" | tr -d '\r\n')
CEPH_ADMIN_KEY=$(ssh $SSH_OPTS ubuntu@$BACKEND_IP "sudo cephadm shell -- ceph auth get-key client.admin 2>/dev/null" | tr -d '\r\n')

if [ -z "$CEPH_FSID" ] || [ -z "$CEPH_ADMIN_KEY" ]; then
  echo "❌ CEPH_FSID 또는 CEPH_ADMIN_KEY 수집 실패. 백엔드 ceph 상태를 확인하세요."
  exit 1
fi
echo "  CEPH_FSID: $CEPH_FSID"

# RBD pool 생성 (rbd pool init은 CSI가 첫 볼륨 생성 시 자동 처리 — hang 방지를 위해 생략)
ssh $SSH_OPTS ubuntu@$BACKEND_IP \
  "sudo cephadm shell -- ceph osd pool create kubernetes 2>/dev/null || true"

echo "=============================="
echo " [5/5] Phase 5: CSI 연동"
echo "=============================="
# 매니페스트 및 스크립트 전송
scp -O $SSH_OPTS -r "$SCRIPT_DIR/manifests" ubuntu@$FRONTEND_IP:~/
scp -O $SSH_OPTS "$SCRIPT_DIR/scripts/04_csi_install.sh" ubuntu@$FRONTEND_IP:~/
scp -O $SSH_OPTS "$SCRIPT_DIR/scripts/05_verify.sh" ubuntu@$FRONTEND_IP:~/

ssh $SSH_OPTS ubuntu@$FRONTEND_IP \
  "sudo BACKEND_PRIVATE_IP='$BACKEND_PRIVATE_IP' \
   CEPH_FSID='$CEPH_FSID' \
   CEPH_ADMIN_KEY='$CEPH_ADMIN_KEY' \
   SCRIPT_DIR=/home/ubuntu \
   bash /home/ubuntu/04_csi_install.sh"

echo ""
echo "✅ k3s-storage-lab 구성 완료"
echo ""
echo "  Frontend   : ssh -i $SSH_KEY ubuntu@$FRONTEND_IP"
echo "  Backend    : ssh -i $SSH_KEY ubuntu@$BACKEND_IP"
echo ""
echo "  다음 단계:"
echo "    ssh -i $SSH_KEY ubuntu@$FRONTEND_IP"
echo ""
echo "  [CSI 검증]"
echo "    bash ~/05_verify.sh"
echo ""
echo "  [Storage Test App 배포]"
echo "    # 1) 이미지 빌드"
echo "    cd ~/manifests/storage-test-app/app"
echo "    docker build -t storage-test-app:latest ."
echo ""
echo "    # 2) k3s containerd에 이미지 임포트"
echo "    docker save storage-test-app:latest | sudo k3s ctr images import -"
echo ""
echo "    # 3) k8s 리소스 적용"
echo "    kubectl apply -f ~/manifests/storage-test-app/k8s/"
echo ""
echo "    # 접근 URL: http://$FRONTEND_IP:30080"
