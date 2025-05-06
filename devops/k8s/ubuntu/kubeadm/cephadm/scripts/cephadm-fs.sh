#!/bin/bash
set -e

# CephFS 설치를 위한 변수 설정 (필요에 따라 수정하세요)
FS_NAME="mycephfs" # 생성할 파일 시스템 이름
METADATA_POOL="${FS_NAME}_metadata"
DATA_POOL="${FS_NAME}_data"
MDS_COUNT=2 # 배포할 MDS 데몬 수
MDS_HOSTS="k8s-worker-1 k8s-worker-2" # 호스트 이름은 'ceph orch host ls' 명령으로 확인 가능
CEPH_CSI_USER="ceph-csi-user" # CSI 드라이버가 사용할 Ceph 클라이언트 사용자 ID (client. 접두사는 자동으로 붙음)
K8S_CSI_NAMESPACE="ceph-csi-cephfs" # CSI 드라이버를 배포할 Kubernetes 네임스페이스
K8S_CSI_RELEASE_NAME="ceph-csi-cephfs-release" # Helm 릴리스 이름
K8S_SECRET_NAME="ceph-csi-cephfs-keyring" # Ceph 키링을 저장할 Kubernetes Secret 이름
K8S_STORAGE_CLASS_NAME="cephfs-sc" # 생성할 Kubernetes StorageClass 이름
K8S_PVC_NAME="my-cephfs-pvc" # 생성할 PersistentVolumeClaim 이름
K8S_TEST_POD_NAME="cephfs-test-pod" # 생성할 테스트 Pod 이름

echo "Cephadm 쉘에 접근하여 CephFS 설치를 시작합니다..."

echo "데이터 풀 '$DATA_POOL' 및 메타데이터 풀 '$METADATA_POOL' 생성..."
# 참고: PG 수는 환경에 맞게 조정해야 합니다. 여기서는 예시로 64를 사용합니다.
ceph osd pool create "$DATA_POOL" 64 replicated
ceph osd pool create "$METADATA_POOL" 64 replicated
echo "풀 생성이 완료되었습니다."

# 2. 데이터 풀과 메타데이터 풀을 사용하여 파일 시스템 생성
echo "파일 시스템 '$FS_NAME' 생성 및 풀 연결..."
ceph fs new "$FS_NAME" "$METADATA_POOL" "$DATA_POOL"
echo "파일 시스템 생성이 완료되었습니다."

# 3. MDS 서비스 배포
echo "MDS 서비스 배포..."
ceph orch apply mds "$FS_NAME" --placement="$MDS_COUNT $MDS_HOSTS"
echo "MDS 서비스 배포 명령이 실행되었습니다."

echo "MDS 데몬이 시작되고 파일 시스템이 생성되기를 기다립니다..."

WAIT_TIME=120
echo "CephFS MDS 배포를 위해 ${WAIT_TIME}초 대기합니다..."
# 카운터 초기화
counter=0
while [ $counter -lt $WAIT_TIME ]; do
  # 화면 지우기 없이 경과 시간만 업데이트
  echo -ne "CephFS MDS 배포를 위해 ${WAIT_TIME}초 대기합니다...(경과시간: ${counter}초)\r"
  sleep 1
  counter=$((counter + 1))
done

# --- 검증 ---
echo "CephFS 배포 상태 확인..."
ceph orch ls | grep mds # 서비스 목록에서 mds 확인
ceph fs ls # 파일 시스템 목록 확인
ceph fs status "$FS_NAME" # 특정 파일 시스템 상태 확인
ceph orch ps --daemon_type=mds # MDS 데몬 프로세스 확인

echo "CephFS 설치 프로세스 완료."
echo "다음 단계: CephFS 클라이언트 사용자를 생성하고, Kubernetes 환경에서는 Ceph CSI 드라이버를 사용하여 CephFS 볼륨을 관리할 수 있습니다."

