#!/bin/bash
set -e
source scripts/.env

SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

echo "=============================="
echo " Step 1: cephadm 설치 (ceph-1)"
echo "=============================="
$CSSH$C1_PUB <<'ENDSSH'
  curl -fsSL https://download.ceph.com/keys/release.asc | sudo gpg --dearmor -o /etc/apt/keyrings/ceph.gpg
  echo "deb [signed-by=/etc/apt/keyrings/ceph.gpg] https://download.ceph.com/debian-reef/ $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/ceph.list
  sudo apt-get update -y
  sudo apt-get install -y cephadm
  sudo cephadm install
ENDSSH

echo "=============================="
echo " Step 1-1: Ceph 클러스터 Bootstrap"
echo "=============================="
CEPH1_PRIV_IP=$C1_PRIV
$CSSH$C1_PUB "sudo cephadm bootstrap \
  --mon-ip $CEPH1_PRIV_IP \
  --initial-dashboard-user admin \
  --initial-dashboard-password admin123! \
  --allow-overwrite \
  --skip-monitoring-stack"

echo "=============================="
echo " Step 1-2: ceph-2, ceph-3 노드 추가"
echo "=============================="
CEPH_PUBKEY=$($CSSH$C1_PUB "sudo cat /etc/ceph/ceph.pub")

for ip in $C2_PUB $C3_PUB; do
  ssh $SSH_OPTS ubuntu@$ip "echo '$CEPH_PUBKEY' | sudo tee -a /root/.ssh/authorized_keys"
done

$CSSH$C1_PUB "
  sudo ceph orch host add ceph-2 $C2_PRIV
  sudo ceph orch host add ceph-3 $C3_PRIV
  sleep 10
"

echo "=============================="
echo " Step 1-3: OSD 추가"
echo "=============================="
$CSSH$C1_PUB "
  sudo ceph orch apply osd --all-available-devices
  sleep 30
  sudo ceph osd tree
"

echo "=============================="
echo " Step 1-4: CephFS + RBD Pool 생성"
echo "=============================="
$CSSH$C1_PUB "
  sudo ceph osd pool create cephfs_data 32
  sudo ceph osd pool create cephfs_metadata 8
  sudo ceph fs new labfs cephfs_metadata cephfs_data

  sudo ceph osd pool create rbd 32
  sudo ceph osd pool application enable rbd rbd
  sudo rbd pool init rbd

  sudo ceph osd pool set cephfs_data size 2
  sudo ceph osd pool set cephfs_metadata size 2
  sudo ceph osd pool set rbd size 2

  echo '--- Ceph 상태 확인 ---'
  sudo ceph status
  sudo ceph df
"

echo "=============================="
echo " Step 1-5: CSI용 ceph 키 추출"
echo "=============================="
$CSSH$C1_PUB "
  sudo ceph auth get-or-create client.k8s \
    mon 'profile rbd' \
    osd 'profile rbd pool=rbd, profile rbd pool=cephfs_data' \
    mds 'allow rw' \
    > /tmp/ceph-client-k8s.keyring
  sudo cat /etc/ceph/ceph.conf
  sudo cat /tmp/ceph-client-k8s.keyring
" > /tmp/ceph-info.txt

echo ""
echo "✅ Step 1 완료 - Ceph 클러스터 구성 완료"
echo "   다음: scripts/02_gpfs_install.sh"
