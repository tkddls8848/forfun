#!/bin/bash
#=========================================================================
# CephFS 설치 스크립트 (Podman 버전)
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

# 네트워크 인자 받기
NETWORK_PREFIX=$1
MASTER_IP=$2
MDS_COUNT=$3  # Vagrantfile에서 전달받은 MDS 개수

echo "=========================================="
echo "CephFS 설치 시작"
echo "=========================================="
echo "네트워크 설정: NETWORK_PREFIX=$NETWORK_PREFIX, MASTER_IP=$MASTER_IP"
echo "MDS 개수: $MDS_COUNT"
echo "=========================================="

# CephFS 기본 설정
export FS_NAME="mycephfs"
export METADATA_POOL="mycephfs_metadata"
export DATA_POOL="mycephfs_data"

# 메타데이터 풀 크기 설정 (조정 가능)
export METADATA_PG_NUM=16  # 기본값: 32 (16GB -> 4GB로 줄임)
export DATA_PG_NUM=64      # 데이터 풀 PG 수 (16GB -> 28GB로 늘림)

# Ceph 클라이언트 사용자 설정
export CEPH_CSI_USER="ceph-csi-user"

#=========================================================================
# 1. CephFS 설치
#=========================================================================
echo -e "\n[단계 1/3] CephFS 파일 시스템 생성을 시작합니다..."

# 데이터 및 메타데이터 풀 생성
echo ">> 데이터 풀 '$DATA_POOL' 및 메타데이터 풀 '$METADATA_POOL' 생성 중..."
echo ">> 데이터 풀 PG 수: $DATA_PG_NUM" 및 메타데이터 풀 PG 수: $METADATA_PG_NUM"
ceph osd pool create "$DATA_POOL" "$DATA_PG_NUM" replicated
ceph osd pool create "$METADATA_POOL" "$METADATA_PG_NUM" replicated

# 파일 시스템 생성
echo ">> 파일 시스템 '$FS_NAME' 생성 및 풀 연결 중..."
ceph fs new "$FS_NAME" "$METADATA_POOL" "$DATA_POOL"

# MDS 서비스 배포
echo ">> MDS 서비스 배포 중..."
ceph orch apply mds "$FS_NAME" --placement="$MDS_COUNT"

echo ">> CephFS 배포 상태 확인 중..."
echo "-- MDS 서비스 목록:"
ceph orch ls | grep mds
echo "-- 파일 시스템 목록:"
ceph fs ls
echo "-- 파일 시스템 '$FS_NAME' 상태:"
ceph fs status "$FS_NAME"

# MDS 서비스 시작 대기
echo ">> MDS 서비스 배포 대기 중..."
MAX_RETRIES=30
RETRY_INTERVAL=30
count=0

while [ $count -lt $MAX_RETRIES ]; do
  if ceph fs status "$FS_NAME" | grep -q "active"; then
    echo ">> MDS 서비스 성공적으로 배포됨"
    break
  fi
  echo "   MDS 배포 대기 중... ($((count+1))/$MAX_RETRIES)"
  sleep $RETRY_INTERVAL
  count=$((count+1))
done

#=========================================================================
# 2. CSI 사용자 생성 및 클러스터 정보 수집
#=========================================================================
echo -e "\n[단계 2/3] CSI 사용자 생성 및 클러스터 정보 수집을 시작합니다..."

# CSI 클라이언트 사용자 생성
echo ">> Ceph 사용자 '$CEPH_CSI_USER' 생성 및 권한 부여 중..."
ceph auth add client.$CEPH_CSI_USER mds 'allow *' mon 'allow *' osd 'allow *' mgr 'allow *'

# 사용자 키링 및 클러스터 정보 수집
CEPH_USER_KEYRING=$(ceph auth get-key client.$CEPH_CSI_USER)
CEPH_CLUSTER_ID=$(ceph fsid)
CEPH_MONITOR_IPS=$(ceph mon dump | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:6789' | tr '\n' ',' | sed 's/,$//')

echo ">> 클러스터 정보:"
echo "   클러스터 ID: $CEPH_CLUSTER_ID"
echo "   모니터 IPs: $CEPH_MONITOR_IPS"
echo "   사용자 키링: $CEPH_USER_KEYRING"

#=========================================================================
# 3. CephFS 마운트 테스트
#=========================================================================
echo -e "\n[단계 3/3] CephFS 마운트 테스트를 시작합니다..."

# 마운트 포인트 생성
MOUNT_POINT="/mnt/cephfs"
echo ">> 마운트 포인트 '$MOUNT_POINT' 생성 중..."
mkdir -p "$MOUNT_POINT"

# CephFS 마운트
echo ">> CephFS 마운트 중..."
ceph-fuse "$MOUNT_POINT"

# 마운트 확인
echo ">> 마운트 상태 확인 중..."
if mountpoint -q "$MOUNT_POINT"; then
    echo ">> CephFS 마운트 성공!"
    echo "   마운트 포인트: $MOUNT_POINT"
    echo "   파일 시스템: $FS_NAME"
    
    # 테스트 파일 생성
    echo ">> 테스트 파일 생성 중..."
    echo "CephFS 테스트 파일 - $(date)" > "$MOUNT_POINT/test.txt"
    echo "   테스트 파일 생성 완료: $MOUNT_POINT/test.txt"
    
    # 파일 내용 확인
    echo ">> 테스트 파일 내용:"
    cat "$MOUNT_POINT/test.txt"
    
    # 마운트 해제
    echo ">> 마운트 해제 중..."
    fusermount -u "$MOUNT_POINT"
    echo ">> 마운트 해제 완료"
else
    echo ">> CephFS 마운트 실패!"
    exit 1
fi

echo -e "\n[완료] CephFS 설치 및 테스트가 완료되었습니다."
echo "=========================================="
echo "CephFS 사용법:"
echo "  - 마운트: ceph-fuse /mnt/cephfs"
echo "  - 해제: fusermount -u /mnt/cephfs"
echo "  - 상태 확인: ceph fs status $FS_NAME"
echo "=========================================="