#!/bin/bash
# Phase 4: Backend — BeeGFS 7.4.6 설치 + 데몬 구성
# 실행: ssh ubuntu@<BACKEND_IP> 'sudo bash -s' < 03_beegfs_backend.sh
set -e

PRIVATE_IP=$(hostname -I | awk '{print $1}')
BEEGFS_VERSION="7.4.6"
BEEGFS_REPO="https://www.beegfs.io/release/beegfs_${BEEGFS_VERSION}"

echo "=============================="
echo " [1/5] APT 저장소 추가"
echo "=============================="
apt-get update -qq

wget -q "${BEEGFS_REPO}/gpg/GPG-KEY-beegfs" -O- \
  | gpg --dearmor > /etc/apt/trusted.gpg.d/beegfs.gpg
echo "deb ${BEEGFS_REPO}/ noble non-free" \
  > /etc/apt/sources.list.d/beegfs.list
apt-get update -qq

echo "=============================="
echo " [2/5] 패키지 설치"
echo "=============================="
# 서버 데몬만 설치 — 클라이언트(beegfs-client-dkms, beegfs-helperd)는 마운트 노드(EC2 #1 CSI)에서만 필요
apt-get install -y \
  beegfs-mgmtd \
  beegfs-meta \
  beegfs-storage \
  beegfs-utils \
  xfsprogs \
  lvm2

echo "=============================="
echo " [3/5] 스토리지 디스크 준비 (xvdd+xvde → LVM 스트라이프 → XFS)"
echo "=============================="
# Nitro 인스턴스: EBS는 /dev/nvme*n1으로 노출됨
# 비루트 디스크 정렬: [0]=xvdb(Ceph#1) [1]=xvdc(Ceph#2) [2]=xvdd(BeeGFS#1) [3]=xvde(BeeGFS#2)
ROOT_DISK=$(lsblk -no pkname "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -1)
echo "  루트 디스크: /dev/${ROOT_DISK}"

EXTRA_DISKS=()
for dev in $(ls /dev/nvme*n1 | sort); do
  [ "$(basename "$dev")" = "$ROOT_DISK" ] && continue
  EXTRA_DISKS+=("$dev")
done
BEEGFS_DEV1="${EXTRA_DISKS[2]:-}"  # 세 번째 비루트 디스크 = xvdd
BEEGFS_DEV2="${EXTRA_DISKS[3]:-}"  # 네 번째 비루트 디스크 = xvde
if [ -z "$BEEGFS_DEV1" ] || [ -z "$BEEGFS_DEV2" ]; then
  echo "❌ BeeGFS 스토리지 디스크 2개(xvdd, xvde)를 찾을 수 없습니다. lsblk:"
  lsblk
  exit 1
fi
echo "  BeeGFS 디스크 #1: $BEEGFS_DEV1 (xvdd)"
echo "  BeeGFS 디스크 #2: $BEEGFS_DEV2 (xvde)"

# LVM 스트라이프: 두 디스크를 beegfs-vg로 묶어 단일 XFS 볼륨 구성
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
echo " [4/5] 서비스 초기화"
echo "=============================="
# mgmtd
/opt/beegfs/sbin/beegfs-setup-mgmtd -p /mnt/beegfs/mgmtd
# 기존 라인(형식 무관) 삭제 후 append — sed 패턴 불일치 방지
sed -i '/connDisableAuthentication/d' /etc/beegfs/beegfs-mgmtd.conf
echo "connDisableAuthentication = true" >> /etc/beegfs/beegfs-mgmtd.conf

# meta
/opt/beegfs/sbin/beegfs-setup-meta \
  -p /mnt/beegfs/meta \
  -s 1 \
  -m "${PRIVATE_IP}"
sed -i '/connDisableAuthentication/d' /etc/beegfs/beegfs-meta.conf
echo "connDisableAuthentication = true" >> /etc/beegfs/beegfs-meta.conf

# storaged
/opt/beegfs/sbin/beegfs-setup-storage \
  -p /mnt/beegfs/storage \
  -s 1 \
  -i 1 \
  -m "${PRIVATE_IP}"
sed -i '/connDisableAuthentication/d' /etc/beegfs/beegfs-storage.conf
echo "connDisableAuthentication = true" >> /etc/beegfs/beegfs-storage.conf

# beegfs-ctl(beegfs-utils)도 beegfs-client.conf를 읽음 — 인증 비활성화 필수
touch /etc/beegfs/beegfs-client.conf
sed -i '/connDisableAuthentication/d' /etc/beegfs/beegfs-client.conf
sed -i '/sysMgmtdHost/d' /etc/beegfs/beegfs-client.conf
{
  echo "sysMgmtdHost              = ${PRIVATE_IP}"
  echo "connDisableAuthentication = true"
} >> /etc/beegfs/beegfs-client.conf

echo "=============================="
echo " [5/5] 데몬 기동"
echo "=============================="
systemctl enable --now beegfs-mgmtd
systemctl enable --now beegfs-meta
systemctl enable --now beegfs-storage

echo "확인 중 (10초 대기)..."
sleep 10
beegfs-ctl --listnodes --nodetype=storage
beegfs-ctl --listnodes --nodetype=meta
echo ""
echo "✅ BeeGFS backend 구성 완료"
echo "   mgmtd IP: ${PRIVATE_IP}:8008"
