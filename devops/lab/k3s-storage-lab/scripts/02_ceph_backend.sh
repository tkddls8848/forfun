#!/bin/bash
# Phase 3: Backend — Ceph 클러스터 구성 실행
# 전제: python3, podman, cephadm, nvme-cli 는 Packer AMI에 사전 설치됨
# 실행: ssh ubuntu@<BACKEND_IP> 'sudo bash -s' < 02_ceph_backend.sh
set -e

PRIVATE_IP=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

echo "=============================="
echo " [1/4] Ceph 클러스터 부트스트랩"
echo "=============================="
# 기존 클러스터가 있으면 먼저 정리
EXISTING_FSID=$(cephadm ls 2>/dev/null | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d[0]['fsid'] if d else '')" 2>/dev/null || true)
if [ -n "$EXISTING_FSID" ]; then
  echo "  기존 클러스터 감지 (fsid: $EXISTING_FSID) — 정리 중..."
  cephadm rm-cluster --force --zap-osds --fsid "$EXISTING_FSID" || true
fi

cephadm bootstrap \
  --mon-ip "${PRIVATE_IP}" \
  --single-host-defaults \
  --skip-monitoring-stack \
  --allow-overwrite

# OSD 자동 탐색 비활성화 — BeeGFS 디스크를 Ceph가 선점하지 않도록
cephadm shell -- ceph orch apply osd --all-available-devices --unmanaged=true

echo "=============================="
echo " [2/4] 단일 노드 복제 설정"
echo "=============================="
cephadm shell -- ceph config set global osd_pool_default_size 1
cephadm shell -- ceph config set global osd_pool_default_min_size 1

cephadm shell -- ceph osd crush rule rm replicated_rule 2>/dev/null || true
cephadm shell -- ceph osd crush rule create-replicated replicated_rule default host

echo "=============================="
echo " [3/4] OSD 추가 (xvdb, xvdc 탐색)"
echo "=============================="
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
  echo "Ceph OSD 디스크 2개를 찾을 수 없습니다. lsblk:"
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
echo " [4/4] CephFS 활성화"
echo "=============================="
cephadm shell -- ceph fs volume create cephfs

cephadm shell -- ceph -s
echo ""
echo "Ceph backend 구성 완료 (Packer AMI)"
echo ""
echo "CSI 연동 정보 수집:"
echo "  fsid        : $(cephadm shell -- ceph fsid 2>/dev/null)"
echo "  admin key   : $(cephadm shell -- ceph auth get-key client.admin 2>/dev/null)"
echo "  mon IP      : ${PRIVATE_IP}"
