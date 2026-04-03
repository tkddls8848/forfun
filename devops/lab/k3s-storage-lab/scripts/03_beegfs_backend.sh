#!/bin/bash
# Phase 4: Backend — BeeGFS conf 및 서비스 기동 실행
# 전제: beegfs-mgmtd, beegfs-meta, beegfs-storage, xfsprogs, lvm2 는 Packer AMI에 사전 설치됨
# 실행: ssh ubuntu@<BACKEND_IP> 'sudo bash -s' < 03_beegfs_backend.sh
set -e

PRIVATE_IP=$(hostname -I | awk '{print $1}')

echo "=============================="
echo " [1/3] 스토리지 디스크 준비 (xvdd+xvde → LVM 스트라이프 → XFS)"
echo "=============================="
ROOT_DISK=$(lsblk -no pkname "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -1)
echo "  루트 디스크: /dev/${ROOT_DISK}"

EXTRA_DISKS=()
for dev in $(ls /dev/nvme*n1 | sort); do
  [ "$(basename "$dev")" = "$ROOT_DISK" ] && continue
  EXTRA_DISKS+=("$dev")
done
BEEGFS_DEV1="${EXTRA_DISKS[2]:-}"
BEEGFS_DEV2="${EXTRA_DISKS[3]:-}"
if [ -z "$BEEGFS_DEV1" ] || [ -z "$BEEGFS_DEV2" ]; then
  echo "BeeGFS 스토리지 디스크 2개(xvdd, xvde)를 찾을 수 없습니다. lsblk:"
  lsblk
  exit 1
fi
echo "  BeeGFS 디스크 #1: $BEEGFS_DEV1 (xvdd)"
echo "  BeeGFS 디스크 #2: $BEEGFS_DEV2 (xvde)"

pvcreate -ff -y "$BEEGFS_DEV1" "$BEEGFS_DEV2"
vgcreate beegfs-vg "$BEEGFS_DEV1" "$BEEGFS_DEV2"
lvcreate -i 2 -l 100%VG -n beegfs-lv beegfs-vg
mkfs.xfs /dev/beegfs-vg/beegfs-lv
mkdir -p /mnt/beegfs/storage
mount /dev/beegfs-vg/beegfs-lv /mnt/beegfs/storage
grep -q "beegfs-vg" /etc/fstab || \
  echo "/dev/beegfs-vg/beegfs-lv /mnt/beegfs/storage xfs defaults 0 0" >> /etc/fstab
mkdir -p /mnt/beegfs/mgmtd /mnt/beegfs/meta

echo "=============================="
echo " [2/3] 서비스 초기화"
echo "=============================="
/opt/beegfs/sbin/beegfs-setup-mgmtd -p /mnt/beegfs/mgmtd
sed -i '/connDisableAuthentication/d' /etc/beegfs/beegfs-mgmtd.conf
echo "connDisableAuthentication = true" >> /etc/beegfs/beegfs-mgmtd.conf

/opt/beegfs/sbin/beegfs-setup-meta \
  -p /mnt/beegfs/meta \
  -s 1 \
  -m "${PRIVATE_IP}"
sed -i '/connDisableAuthentication/d' /etc/beegfs/beegfs-meta.conf
echo "connDisableAuthentication = true" >> /etc/beegfs/beegfs-meta.conf

/opt/beegfs/sbin/beegfs-setup-storage \
  -p /mnt/beegfs/storage \
  -s 1 \
  -i 1 \
  -m "${PRIVATE_IP}"
sed -i '/connDisableAuthentication/d' /etc/beegfs/beegfs-storage.conf
echo "connDisableAuthentication = true" >> /etc/beegfs/beegfs-storage.conf

touch /etc/beegfs/beegfs-client.conf
sed -i '/connDisableAuthentication/d' /etc/beegfs/beegfs-client.conf
sed -i '/sysMgmtdHost/d' /etc/beegfs/beegfs-client.conf
{
  echo "sysMgmtdHost              = ${PRIVATE_IP}"
  echo "connDisableAuthentication = true"
} >> /etc/beegfs/beegfs-client.conf

echo "=============================="
echo " [3/3] 데몬 기동"
echo "=============================="
systemctl enable --now beegfs-mgmtd
systemctl enable --now beegfs-meta
systemctl enable --now beegfs-storage

echo "확인 중 (10초 대기)..."
sleep 10
beegfs-ctl --listnodes --nodetype=storage
beegfs-ctl --listnodes --nodetype=meta
echo ""
echo "BeeGFS backend 구성 완료 (Packer AMI)"
echo "   mgmtd IP: ${PRIVATE_IP}:8008"
