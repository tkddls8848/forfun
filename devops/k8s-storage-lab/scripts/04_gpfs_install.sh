#!/bin/bash
set -e
source scripts/.env

SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"
CSCP="scp $SSH_OPTS"

GPFS_PKG_DIR="./gpfs-packages"
if [ ! -d "$GPFS_PKG_DIR" ]; then
  echo "❌ $GPFS_PKG_DIR 디렉토리가 없습니다."
  echo "   IBM Spectrum Scale Developer Edition을 다운로드 후"
  echo "   $GPFS_PKG_DIR/ 에 .deb 패키지를 넣어주세요."
  echo "   다운로드: https://www.ibm.com/account/reg/us-en/signup?formid=urx-41728"
  exit 1
fi

# GPFS 클라이언트: master-1, worker-1~4 / GPFS 서버: nsd-1, nsd-2
ALL_NODES_PUB=($M1_PUB $W1_PUB $W2_PUB $W3_PUB $W4_PUB $N1_PUB $N2_PUB)

echo "=============================="
echo " Step 2: GPFS 패키지 전송 및 설치"
echo "=============================="
for ip in "${ALL_NODES_PUB[@]}"; do
  echo "  패키지 전송 → $ip"
  $CSCP -r $GPFS_PKG_DIR ubuntu@$ip:/tmp/gpfs-packages

  echo "  GPFS 설치 → $ip"
  $CSSH$ip <<'ENDSSH'
    cd /tmp/gpfs-packages
    sudo apt-get install -y ksh perl libaio1 libssl-dev \
      linux-headers-$(uname -r) build-essential dkms

    sudo dpkg -i gpfs.base_*.deb       || true
    sudo dpkg -i gpfs.gpl_*.deb        || true
    sudo dpkg -i gpfs.adv_*.deb        || true
    sudo dpkg -i gpfs.crypto_*.deb     || true
    sudo dpkg -i gpfs.ext_*.deb        || true
    sudo apt-get install -f -y

    sudo /usr/lpp/mmfs/bin/mmbuildgpl
ENDSSH
  echo "  ✓ GPFS 설치 완료: $ip"
done

echo "=============================="
echo " Step 2-1: SSH 접근 확인 (nsd-1 기준)"
echo "=============================="
$CSSH$N1_PUB "
  for host in master-1 worker-1 worker-2 worker-3 worker-4 nsd-1 nsd-2; do
    ssh -o StrictHostKeyChecking=no ubuntu@\$host 'echo \$host ok' || echo \"WARN: \$host 접근 실패\"
  done
"

echo ""
echo "✅ Step 4 완료 - 다음: scripts/05_nsd_setup.sh"
