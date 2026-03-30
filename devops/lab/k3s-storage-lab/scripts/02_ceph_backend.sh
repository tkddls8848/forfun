#!/bin/bash
# Phase 3: Backend — cephadm 설치 + Ceph 클러스터 구성
# 실행: ssh ubuntu@<BACKEND_IP> 'sudo bash -s' < 02_ceph_backend.sh
set -e

PRIVATE_IP=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

echo "=============================="
echo " [1/5] 사전 준비"
echo "=============================="
# 커널 고정
apt-mark hold linux-image-* linux-headers-* 2>/dev/null || true

# 의존성 설치 (nvme-cli 포함 — Nitro NVMe 장치 탐색 필수)
apt-get update -qq
apt-get install -y python3 podman cephadm nvme-cli

echo "=============================="
echo " [2/5] Ceph 클러스터 부트스트랩"
echo "=============================="
cephadm bootstrap \
  --mon-ip "${PRIVATE_IP}" \
  --single-host-defaults \
  --skip-monitoring-stack \
  --allow-overwrite

# OSD 자동 탐색 비활성화 — BeeGFS 디스크(nvme2n1)를 Ceph가 선점하지 않도록
cephadm shell -- ceph orch apply osd --all-available-devices --unmanaged=true

echo "=============================="
echo " [3/5] 단일 노드 복제 설정"
echo "=============================="
cephadm shell -- ceph config set global osd_pool_default_size 1
cephadm shell -- ceph config set global osd_pool_default_min_size 1

# 단일 노드: crush rule 조정
cephadm shell -- ceph osd crush rule rm replicated_rule 2>/dev/null || true
cephadm shell -- ceph osd crush rule create-replicated replicated_rule default host

echo "=============================="
echo " [4/5] OSD 추가 (xvdb, xvdc 탐색)"
echo "=============================="
# Nitro 인스턴스: EBS는 /dev/nvme*n1으로 노출됨
# 루트 디스크 제외 후 정렬 — xvdb=첫번째, xvdc=두번째 비루트 디스크
ROOT_DISK=$(lsblk -no pkname "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -1)
echo "  루트 디스크: /dev/${ROOT_DISK}"

EXTRA_DISKS=()
for dev in $(ls /dev/nvme*n1 | sort); do
  [ "$(basename "$dev")" = "$ROOT_DISK" ] && continue
  EXTRA_DISKS+=("$dev")
done
OSD_DEV1="${EXTRA_DISKS[0]:-}"
OSD_DEV2="${EXTRA_DISKS[1]:-}"
if [ -z "$OSD_DEV1" ] || [ -z "$OSD_DEV2" ]; then
  echo "❌ Ceph OSD 디스크 2개를 찾을 수 없습니다. lsblk:"
  lsblk
  exit 1
fi
echo "  Ceph OSD 디스크 #1: $OSD_DEV1 (xvdb)"
echo "  Ceph OSD 디스크 #2: $OSD_DEV2 (xvdc)"

cephadm shell -- ceph orch daemon add osd "${HOSTNAME}:${OSD_DEV1}"
cephadm shell -- ceph orch daemon add osd "${HOSTNAME}:${OSD_DEV2}"
echo "OSD 준비 대기 (60초)..."
sleep 60
cephadm shell -- ceph osd tree

echo "=============================="
echo " [5/5] CephFS 활성화"
echo "=============================="
cephadm shell -- ceph fs volume create cephfs

echo "상태 확인..."
cephadm shell -- ceph -s
echo ""
echo "✅ Ceph backend 구성 완료"
echo ""
echo "CSI 연동 정보 수집:"
echo "  fsid        : $(cephadm shell -- ceph fsid 2>/dev/null)"
echo "  admin key   : $(cephadm shell -- ceph auth get-key client.admin 2>/dev/null)"
echo "  mon IP      : ${PRIVATE_IP}"
