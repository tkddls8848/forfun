#!/bin/bash
set -e
source scripts/.env

SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

WORKER_COUNT=${#WORKER_PUBS[@]}
CLUSTER_NAME="gpfslab"
FS_NAME="gpfs0"
MOUNT_POINT="/gpfs/gpfs0"

echo "=============================="
echo " Step 3: GPFS 클러스터 생성"
echo "=============================="
NODEFILE_WORKERS=""
for i in $(seq 1 $WORKER_COUNT); do
  NODEFILE_WORKERS+="worker-$i:\n"
done
CLIENT_LIST="master-1"
for i in $(seq 1 $WORKER_COUNT); do CLIENT_LIST+=",worker-$i"; done

$CSSH$N1_PUB "
  printf 'nsd-1:quorum-manager\nnsd-2:quorum-manager\nmaster-1:quorum\n${NODEFILE_WORKERS}' \
    | sudo tee /tmp/NodeFile

  sudo /usr/lpp/mmfs/bin/mmcrcluster \
    -N /tmp/NodeFile \
    -C $CLUSTER_NAME \
    -p nsd-1 \
    -s nsd-2

  sudo /usr/lpp/mmfs/bin/mmchlicense client --accept -N $CLIENT_LIST
  sudo /usr/lpp/mmfs/bin/mmchlicense server --accept -N nsd-1,nsd-2

  echo '--- 클러스터 확인 ---'
  sudo /usr/lpp/mmfs/bin/mmlscluster
"

echo "=============================="
echo " Step 3-1: NSD 디스크 정의"
echo "=============================="
$CSSH$N1_PUB "
  sudo tee /tmp/NSDFile <<EOF
%nsd:
  device=/dev/nvme1n1
  nsd=nsd1disk
  servers=nsd-1,nsd-2
  usage=dataAndMetadata
  failureGroup=1

%nsd:
  device=/dev/nvme1n1
  nsd=nsd2disk
  servers=nsd-2,nsd-1
  usage=dataAndMetadata
  failureGroup=2
EOF

  sudo /usr/lpp/mmfs/bin/mmcrnsd -F /tmp/NSDFile
  echo '--- NSD 확인 ---'
  sudo /usr/lpp/mmfs/bin/mmlsnsd
"

echo "=============================="
echo " Step 3-2: GPFS 파일시스템 생성"
echo "=============================="
$CSSH$N1_PUB "
  sudo /usr/lpp/mmfs/bin/mmcrfs $FS_NAME \
    -F /tmp/NSDFile \
    -A yes \
    -B 256K \
    -m 2 -M 2 \
    -r 2 -R 2

  echo '--- 파일시스템 확인 ---'
  sudo /usr/lpp/mmfs/bin/mmlsfs $FS_NAME
"

echo "=============================="
echo " Step 3-3: GPFS 데몬 시작 및 마운트"
echo "=============================="
ALL_GPFS_PUB=($N1_PUB $N2_PUB $M1_PUB "${WORKER_PUBS[@]}")

for ip in "${ALL_GPFS_PUB[@]}"; do
  $CSSH$ip "sudo /usr/lpp/mmfs/bin/mmstartup"
  echo "  mmstartup: $ip"
done

sleep 15

$CSSH$N1_PUB "
  sudo /usr/lpp/mmfs/bin/mmgetstate -a
  sudo mkdir -p $MOUNT_POINT
  sudo /usr/lpp/mmfs/bin/mmmount $FS_NAME -a

  echo '--- 마운트 확인 ---'
  df -h | grep $FS_NAME
  sudo /usr/lpp/mmfs/bin/mmlsmount $FS_NAME -L
"

echo ""
echo "✅ Step 3 완료 - 마운트 포인트: $MOUNT_POINT"
echo "   다음: scripts/06_csi_gpfs.sh"
