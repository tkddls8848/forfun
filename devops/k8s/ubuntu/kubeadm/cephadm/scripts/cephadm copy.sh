#!/bin/bash
#=========================================================================
# CephFS 설치 및 Kubernetes 연동 통합 스크립트
# 목적: CephFS 파일 시스템 설치 및 Kubernetes CSI 드라이버 연동
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

#-------------------------------------------------------------------------
# 1. 설정 변수
#-------------------------------------------------------------------------
# CephFS 기본 설정
FS_NAME="mycephfs"                 # 생성할 파일 시스템 이름
METADATA_POOL="${FS_NAME}_metadata"  # 메타데이터 저장 풀 이름
DATA_POOL="${FS_NAME}_data"        # 데이터 저장 풀 이름
MDS_COUNT=2

# Ceph 클라이언트 사용자 설정
CEPH_CSI_USER="ceph-csi-user"      # CSI 드라이버용 사용자 ID

# Kubernetes 설정
K8S_CSI_NAMESPACE="ceph-csi-cephfs"     # CSI 드라이버 배포 네임스페이스
K8S_CSI_RELEASE_NAME="ceph-csi-cephfs-release"  # Helm 릴리스 이름
K8S_SECRET_NAME="ceph-csi-cephfs-keyring"  # Ceph 키링 저장 Secret
K8S_STORAGE_CLASS_NAME="cephfs-sc"      # StorageClass 이름
K8S_PVC_NAME="my-cephfs-pvc"           # 테스트용 PVC 이름
K8S_TEST_POD_NAME="cephfs-test-pod"     # 테스트용 Pod 이름

#=========================================================================
# 2. CephFS 설치
#=========================================================================
echo -e "\n[단계 1/7] CephFS 파일 시스템 생성을 시작합니다..."

#-------------------------------------------------------------------------
# 2.1 데이터 및 메타데이터 풀 생성
#-------------------------------------------------------------------------
echo ">> 데이터 풀 '$DATA_POOL' 및 메타데이터 풀 '$METADATA_POOL' 생성 중..."
# 참고: PG 수는 환경에 맞게 조정 필요 (여기서는 예시로 64 사용)
ceph osd pool create "$DATA_POOL" 64 replicated
ceph osd pool create "$METADATA_POOL" 64 replicated
echo ">> 풀 생성 완료"

#-------------------------------------------------------------------------
# 2.2 파일 시스템 생성
#-------------------------------------------------------------------------
echo ">> 파일 시스템 '$FS_NAME' 생성 및 풀 연결 중..."
ceph fs new "$FS_NAME" "$METADATA_POOL" "$DATA_POOL"
echo ">> 파일 시스템 생성 완료"

#-------------------------------------------------------------------------
# 2.3 MDS 서비스 배포
#-------------------------------------------------------------------------
echo ">> MDS 서비스 배포 중..."
ceph orch apply mds "$FS_NAME" --placement="$MDS_COUNT"
echo ">> MDS 서비스 배포 명령 실행 완료"

echo ">> CephFS 배포 상태 확인 중..."
echo "-- MDS 서비스 목록:"
ceph orch ls | grep mds
echo "-- 파일 시스템 목록:"
ceph fs ls
echo "-- 파일 시스템 '$FS_NAME' 상태:"
ceph fs status "$FS_NAME"
echo "-- MDS 데몬 프로세스 상태:"
ceph orch apply mds "$FS_NAME" --placement="$MDS_COUNT"
ceph orch ps --daemon_type=mds
echo "[단계 1/7] CephFS 파일 시스템 설치 완료"

# MDS 데몬 시작 대기
WAIT_TIME=120
echo ">> MDS 데몬  배포 대기 (${WAIT_TIME}초)..."
counter=0
while [ $counter -lt $WAIT_TIME ]; do
  echo -ne "   MDS 데몬  배포 진행 중... (경과: ${counter}초/${WAIT_TIME}초)\r"
  sleep 1
  counter=$((counter + 1))
done
echo -e "\n>> MDS 데몬  배포 대기 완료"

#=========================================================================
# 3. CSI 사용자 생성 및 클러스터 정보 수집
#=========================================================================
echo -e "\n[단계 2/7] CSI 사용자 생성 및 클러스터 정보 수집을 시작합니다..."

#-------------------------------------------------------------------------
# 3.1 CSI 클라이언트 사용자 생성
#-------------------------------------------------------------------------
echo ">> Ceph 사용자 '$CEPH_CSI_USER' 생성 및 권한 부여 중..."
# 모든 권한 부여 (실제 환경에서는 최소 권한 부여 권장)
ceph auth add client.$CEPH_CSI_USER mds 'allow *' mon 'allow *' osd 'allow *' mgr 'allow *'
echo ">> 사용자 생성 완료"

#-------------------------------------------------------------------------
# 3.2 사용자 키링 및 클러스터 정보 수집
#-------------------------------------------------------------------------
echo ">> Ceph 사용자 키링 및 클러스터 정보 수집 중..."
# 키링 가져오기
CEPH_USER_KEYRING=$(ceph auth get-key client.$CEPH_CSI_USER)

# 클러스터 ID 가져오기
CEPH_CLUSTER_ID=$(ceph fsid)

# 모니터 주소 목록 가져오기 (콤마로 구분된 IP:Port 형식)
CEPH_MONITOR_IPS=$(ceph mon dump | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:6789' | tr '\n' ',' | sed 's/,$//')

# 수집된 정보 확인
echo ">> 수집된 Ceph 클러스터 정보:"
echo "   - Cluster ID: $CEPH_CLUSTER_ID"
echo "   - Monitor IPs: $CEPH_MONITOR_IPS"
echo "   - User Keyring (client.$CEPH_CSI_USER): *****" # 보안상 키링 값은 마스킹 처리
echo "[단계 2/7] CSI 사용자 생성 및 클러스터 정보 수집 완료"

#=========================================================================
# 4. Kubernetes Secret 생성
#=========================================================================
echo -e "\n[단계 3/7] Kubernetes Secret 생성을 시작합니다..."

# Secret YAML 파일 생성
echo ">> Kubernetes Secret YAML 파일 생성 중..."
cat > ceph-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: $K8S_SECRET_NAME
  namespace: $K8S_CSI_NAMESPACE
stringData:
  adminID: $CEPH_CSI_USER
  adminKey: $CEPH_USER_KEYRING
  userID: $CEPH_CSI_USER
  userKey: $CEPH_USER_KEYRING
EOF
echo ">> Secret YAML 파일 생성 완료: ceph-secret.yaml"

# 네임스페이스 및 Secret 생성
echo ">> Kubernetes 네임스페이스 및 Secret 생성 중..."
kubectl create namespace $K8S_CSI_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f ceph-secret.yaml -n $K8S_CSI_NAMESPACE
echo "[단계 3/7] Kubernetes Secret 생성 완료"

#=========================================================================
# 5. Ceph CSI 드라이버 설치 (Helm 사용)
#=========================================================================
echo -e "\n[단계 4/7] Ceph CSI 드라이버 설치를 시작합니다..."

#-------------------------------------------------------------------------
# 5.1 Helm 설치 (없는 경우)
#-------------------------------------------------------------------------
echo ">> Helm 설치 여부 확인 및 필요시 설치 중..."
if ! command -v helm &> /dev/null; then
  echo "   Helm이 설치되어 있지 않습니다. 설치를 진행합니다..."
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh
  echo "   Helm 설치 완료"
else
  echo "   Helm이 이미 설치되어 있습니다."
fi

#-------------------------------------------------------------------------
# 5.2 Ceph CSI Helm 저장소 추가
#-------------------------------------------------------------------------
echo ">> Ceph CSI Helm 저장소 추가 및 업데이트 중..."
helm repo add ceph-csi https://ceph.github.io/csi-charts
helm repo update
echo ">> Helm 저장소 업데이트 완료"

#-------------------------------------------------------------------------
# 5.3 Ceph CSI 설치를 위한 values.yaml 생성
#-------------------------------------------------------------------------
echo ">> Ceph CSI 설치를 위한 values.yaml 파일 생성 중..."
cat << EOF > cephfs-csi-values.yaml
csiConfig:
  - clusterID: "$CEPH_CLUSTER_ID" # Ceph 클러스터의 고유 ID
    monitors: # Ceph 모니터 주소 목록
$(echo "$CEPH_MONITOR_IPS" | tr ',' '\n' | sed 's/^/    - /') # 문자열을 YAML 목록 형식으로 변환
secrets:
  - name: "$K8S_SECRET_NAME" # Kubernetes Secret 이름
provisioner:
  # StorageClass에서 사용할 CephFS 파일 시스템 이름
  fsName: "$FS_NAME"
EOF
echo ">> values.yaml 파일 생성 완료: cephfs-csi-values.yaml"

#-------------------------------------------------------------------------
# 5.4 Helm으로 Ceph CSI 드라이버 설치
#-------------------------------------------------------------------------
echo ">> Helm을 사용하여 Ceph CSI 드라이버 설치 중..."
helm install --namespace "$K8S_CSI_NAMESPACE" "$K8S_CSI_RELEASE_NAME" ceph-csi/ceph-csi-cephfs -f cephfs-csi-values.yaml --version 3.9.0
echo ">> Ceph CSI 드라이버 설치 명령 실행 완료"

# CSI 드라이버 배포 대기
WAIT_TIME=120
echo ">> CSI 드라이버 배포 대기 (${WAIT_TIME}초)..."
counter=0
while [ $counter -lt $WAIT_TIME ]; do
  echo -ne "   CSI 드라이버 배포 진행 중... (경과: ${counter}초/${WAIT_TIME}초)\r"
  sleep 1
  counter=$((counter + 1))
done
echo -e "\n>> CSI 드라이버 배포 대기 완료"

# CSI 드라이버 상태 확인
echo ">> CSI 드라이버 배포 상태 확인:"
kubectl get pods -n "$K8S_CSI_NAMESPACE"
echo "[단계 4/7] Ceph CSI 드라이버 설치 완료"

#=========================================================================
# 6. Kubernetes StorageClass 생성
#=========================================================================
echo -e "\n[단계 5/7] Kubernetes StorageClass 생성을 시작합니다..."

# StorageClass YAML 파일 생성
echo ">> StorageClass YAML 파일 생성 중..."
cat << EOF > cephfs-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $K8S_STORAGE_CLASS_NAME
provisioner: cephfs.csi.ceph.com # CephFS CSI 드라이버 프로비저너
parameters:
  clusterID: "$CEPH_CLUSTER_ID" # CSI 드라이버의 clusterID와 일치해야 함
  fsName: "$FS_NAME" # 사용할 CephFS 파일 시스템 이름
  pool: "$DATA_POOL" # 데이터 풀 지정
  # 모니터 주소 직접 지정
  monitors: "$CEPH_MONITOR_IPS"
  mounter: kernel
  # DNS SRV 검색 관련 파라미터
  dnsResolveSrvRecord: "false"
  disableDnsSrvLookup: "true"
  # CSI Secret 이름을 지정하여 인증 정보를 참조
  csi.storage.k8s.io/provisioner-secret-name: "$K8S_SECRET_NAME"
  csi.storage.k8s.io/provisioner-secret-namespace: "$K8S_CSI_NAMESPACE"
  csi.storage.k8s.io/node-stage-secret-name: "$K8S_SECRET_NAME"
  csi.storage.k8s.io/node-stage-secret-namespace: "$K8S_CSI_NAMESPACE"
  csi.storage.k8s.io/controller-expand-secret-name: "$K8S_SECRET_NAME" 
  csi.storage.k8s.io/controller-expand-secret-namespace: "$K8S_CSI_NAMESPACE"
reclaimPolicy: Delete # PV 삭제 시 데이터도 삭제 (Retain 가능)
allowVolumeExpansion: true # 볼륨 확장 허용 여부
mountOptions: # 마운트 옵션 (선택 사항)
  - debug
EOF
echo ">> StorageClass YAML 파일 생성 완료: cephfs-storageclass.yaml"

# StorageClass 생성
echo ">> StorageClass 생성 중..."
kubectl apply -f cephfs-storageclass.yaml
echo ">> StorageClass 생성 완료"

# StorageClass 상태 확인
echo ">> StorageClass 상태 확인:"
kubectl get storageclass "$K8S_STORAGE_CLASS_NAME"
echo "[단계 5/7] Kubernetes StorageClass 생성 완료"

#=========================================================================
# 7. PersistentVolumeClaim (PVC) 생성
#=========================================================================
echo -e "\n[단계 6/7] PersistentVolumeClaim (PVC) 생성을 시작합니다..."

# PVC YAML 파일 생성
echo ">> PVC YAML 파일 생성 중..."
cat << EOF > cephfs-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $K8S_PVC_NAME
spec:
  accessModes:
    - ReadWriteMany # CephFS의 장점인 다중 Pod 동시 접근 가능
  resources:
    requests:
      storage: 1Gi # 요청할 스토리지 용량
  storageClassName: "$K8S_STORAGE_CLASS_NAME" # 사용할 StorageClass 이름
EOF
echo ">> PVC YAML 파일 생성 완료: cephfs-pvc.yaml"

# PVC 생성
echo ">> PVC 생성 중..."
kubectl apply -f cephfs-pvc.yaml
echo ">> PVC 생성 완료"

# PVC 상태 확인
echo ">> PVC 상태 확인:"
kubectl get pvc "$K8S_PVC_NAME"
echo "[단계 6/7] PersistentVolumeClaim 생성 완료"

#=========================================================================
# 8. 테스트 Pod 생성
#=========================================================================
echo -e "\n[단계 7/7] 테스트 Pod 생성을 시작합니다..."

# 테스트 Pod YAML 파일 생성
echo ">> 테스트 Pod YAML 파일 생성 중..."
cat << EOF > cephfs-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: $K8S_TEST_POD_NAME
spec:
  containers:
  - name: test-container
    image: busybox
    command: ['sh', '-c', 'ls -la /mnt/cephfs && echo "CephFS PVC 연결 확인 완료" && sleep 3600']
    volumeMounts:
    - name: cephfs-storage # Pod 내부 볼륨 마운트 이름
      mountPath: /mnt/cephfs # 볼륨을 마운트할 경로
  volumes:
  - name: cephfs-storage # Pod 내부 볼륨 이름
    persistentVolumeClaim:
      claimName: "$K8S_PVC_NAME" # 사용할 PVC 이름
      readOnly: false # 읽기/쓰기 가능 설정
EOF
echo ">> 테스트 Pod YAML 파일 생성 완료: cephfs-test-pod.yaml"
kubectl apply -f cephfs-test-pod.yaml
echo ">> 테스트 Pod 생성 완료"

# 테스트 Pod 상태 확인
echo ">> 테스트 Pod 상태 확인:"
kubectl get pod "$K8S_TEST_POD_NAME"
echo "[단계 7/7] 테스트 Pod 생성 완료"

#=========================================================================
# 9. 설치 완료 및 검증 안내
#=========================================================================
echo -e "\n[완료] CephFS 및 Kubernetes 연동 설치가 완료되었습니다."
echo -e "\n===== 설치 검증 방법 ====="
echo "1. PVC 상태 확인 (Bound 상태여야 함):"
echo "   kubectl get pvc $K8S_PVC_NAME"
echo ""
echo "2. Pod 상태 확인 (Running 상태여야 함):"
echo "   kubectl get pod $K8S_TEST_POD_NAME"
echo ""
echo "3. 테스트 파일 내용 확인:"
echo "   kubectl exec $K8S_TEST_POD_NAME -- cat /mnt/cephfs/hello.txt"
echo ""
echo "4. 여러 Pod에서 공유 파일 시스템 테스트 (필요시):"
echo "   - 추가 Pod YAML 파일을 생성하고 동일한 PVC를 마운트"
echo "   - 한 Pod에서 작성한 파일을 다른 Pod에서 읽기/수정 테스트"
echo ""
echo "===== 리소스 정리 방법 ====="
echo "1. 테스트 리소스 삭제:"
echo "   kubectl delete -f cephfs-test-pod.yaml,cephfs-pvc.yaml,cephfs-storageclass.yaml"
echo ""
echo "2. CSI 드라이버 제거:"
echo "   helm uninstall $K8S_CSI_RELEASE_NAME -n $K8S_CSI_NAMESPACE && kubectl delete namespace $K8S_CSI_NAMESPACE"
echo ""
echo "3. Ceph 사용자 제거:"
echo "   ceph auth del client.$CEPH_CSI_USER"
echo ""
echo "4. CephFS 제거 (주의: 모든 데이터가 삭제됩니다):"
echo "   ceph fs rm $FS_NAME --yes-i-really-mean-it"
echo "   ceph osd pool rm $DATA_POOL $DATA_POOL --yes-i-really-really-mean-it"
echo "   ceph osd pool rm $METADATA_POOL $METADATA_POOL --yes-i-really-really-mean-it"
echo ""
echo "설치 및 검증 결과에 문제가 있는 경우 로그를 확인하세요."
echo "CephFS 관련 이슈: ceph fs status $FS_NAME"
echo "CSI 드라이버 이슈: kubectl logs -n $K8S_CSI_NAMESPACE -l app=ceph-csi-cephfs"