#!/bin/bash
#=========================================================================
# CephFS 설치 및 Kubernetes 연동 통합 스크립트
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

# 네트워크 인자 받기
NETWORK_PREFIX=$1
MASTER_IP=$2
CSI_VERSION=$3
echo "네트워크 설정: NETWORK_PREFIX=$NETWORK_PREFIX, CSI_VERSION=$CSI_VERSION, MASTER_IP=$MASTER_IP"

# CephFS 기본 설정
export FS_NAME="mycephfs"
export METADATA_POOL="mycephfs_metadata"
export DATA_POOL="mycephfs_data"
export MDS_COUNT=2

# Ceph 클라이언트 사용자 설정
export CEPH_CSI_USER="ceph-csi-user"

# Kubernetes 설정
export K8S_CSI_NAMESPACE="ceph-csi-cephfs"
export K8S_CSI_RELEASE_NAME="ceph-csi-cephfs-release"
export K8S_SECRET_NAME="ceph-csi-cephfs-keyring"
export K8S_STORAGE_CLASS_NAME="cephfs-sc"
export K8S_PVC_NAME="my-cephfs-pvc"
export K8S_TEST_POD_NAME="cephfs-test-pod"

#=========================================================================
# 1. CephFS 설치
#=========================================================================
echo -e "\n[단계 1/7] CephFS 파일 시스템 생성을 시작합니다..."

# 데이터 및 메타데이터 풀 생성
echo ">> 데이터 풀 '$DATA_POOL' 및 메타데이터 풀 '$METADATA_POOL' 생성 중..."
ceph osd pool create "$DATA_POOL" 64 replicated
ceph osd pool create "$METADATA_POOL" 64 replicated

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
MAX_RETRIES=20
RETRY_INTERVAL=10
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
echo -e "\n[단계 2/7] CSI 사용자 생성 및 클러스터 정보 수집을 시작합니다..."

# CSI 클라이언트 사용자 생성
echo ">> Ceph 사용자 '$CEPH_CSI_USER' 생성 및 권한 부여 중..."
ceph auth add client.$CEPH_CSI_USER mds 'allow *' mon 'allow *' osd 'allow *' mgr 'allow *'

# 사용자 키링 및 클러스터 정보 수집
CEPH_USER_KEYRING=$(ceph auth get-key client.$CEPH_CSI_USER)
CEPH_CLUSTER_ID=$(ceph fsid)
CEPH_MONITOR_IPS=$(ceph mon dump | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:6789' | tr '\n' ',' | sed 's/,$//')

#=========================================================================
# 3. Kubernetes Secret 생성
#=========================================================================
echo -e "\n[단계 3/7] Kubernetes Secret 생성을 시작합니다..."

# Secret YAML 파일 생성
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

# 네임스페이스 및 Secret 생성
kubectl create namespace $K8S_CSI_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f ceph-secret.yaml -n $K8S_CSI_NAMESPACE

#=========================================================================
# 4. Ceph CSI 드라이버 설치 (Helm 사용)
#=========================================================================
echo -e "\n[단계 4/7] Ceph CSI 드라이버 설치를 시작합니다..."

# Helm 저장소는 이미 추가되어 있음 (cephadm-setup.sh에서)

# Ceph CSI 설치를 위한 values.yaml 생성
cat << EOF > cephfs-csi-values.yaml
csiConfig:
  - clusterID: "$CEPH_CLUSTER_ID"
    monitors:
$(echo "$CEPH_MONITOR_IPS" | tr ',' '\n' | sed 's/^/    - /')
secrets:
  - name: "$K8S_SECRET_NAME"
provisioner:
  fsName: "$FS_NAME"
EOF

# Helm으로 Ceph CSI 드라이버 설치
helm install --namespace "$K8S_CSI_NAMESPACE" "$K8S_CSI_RELEASE_NAME" ceph-csi/ceph-csi-cephfs -f cephfs-csi-values.yaml --version $CSI_VERSION

# CSI 드라이버 배포 대기
echo ">> CSI 드라이버 배포 120초 대기..."
sleep 120
kubectl get pods -n "$K8S_CSI_NAMESPACE"

#=========================================================================
# 5. Kubernetes StorageClass 생성
#=========================================================================
echo -e "\n[단계 5/7] Kubernetes StorageClass 생성을 시작합니다..."

# StorageClass YAML 파일 생성
cat << EOF > cephfs-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $K8S_STORAGE_CLASS_NAME
provisioner: cephfs.csi.ceph.com
parameters:
  clusterID: "$CEPH_CLUSTER_ID"
  fsName: "$FS_NAME"
  pool: "$DATA_POOL"
  mounter: "fuse"
  monitors: "$CEPH_MONITOR_IPS"
  dnsResolveSrvRecord: "false"
  disableDnsSrvLookup: "true"
  csi.storage.k8s.io/provisioner-secret-name: "$K8S_SECRET_NAME"
  csi.storage.k8s.io/provisioner-secret-namespace: "$K8S_CSI_NAMESPACE"
  csi.storage.k8s.io/node-stage-secret-name: "$K8S_SECRET_NAME"
  csi.storage.k8s.io/node-stage-secret-namespace: "$K8S_CSI_NAMESPACE"
  csi.storage.k8s.io/controller-expand-secret-name: "$K8S_SECRET_NAME" 
  csi.storage.k8s.io/controller-expand-secret-namespace: "$K8S_CSI_NAMESPACE"
reclaimPolicy: Delete
allowVolumeExpansion: true
mountOptions:
  - debug
EOF

kubectl apply -f cephfs-storageclass.yaml

#=========================================================================
# 6. PersistentVolumeClaim (PVC) 생성
#=========================================================================
echo -e "\n[단계 6/7] PersistentVolumeClaim (PVC) 생성을 시작합니다..."

# PVC YAML 파일 생성
cat << EOF > cephfs-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $K8S_PVC_NAME
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: "$K8S_STORAGE_CLASS_NAME"
EOF

kubectl apply -f cephfs-pvc.yaml
echo ">> PVC YAML 파일 배포 40초 대기..."
sleep 40
kubectl get pvc "$K8S_PVC_NAME"

#=========================================================================
# 7. 테스트 Pod 생성
#=========================================================================
echo -e "\n[단계 7/7] 테스트 Pod 생성을 시작합니다..."

# 테스트 Pod YAML 파일 생성
cat << EOF > cephfs-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: $K8S_TEST_POD_NAME
spec:
  containers:
  - name: nginx
    image: nginx
    ports:
    - containerPort: 80
    volumeMounts:
    - name: cephfs-data
      mountPath: /usr/share/nginx/html
  volumes:
  - name: cephfs-data
    persistentVolumeClaim:
      claimName: "$K8S_PVC_NAME"
EOF

kubectl apply -f cephfs-test-pod.yaml
kubectl get pod "$K8S_TEST_POD_NAME"

#=========================================================================
# 8. 설치 완료 및 검증 안내
#=========================================================================
echo -e "\n[완료] CephFS 및 Kubernetes 연동 설치가 완료되었습니다."
echo -e "\n===== 설치 검증 방법 ====="
echo "1. PVC 상태 확인: kubectl get pvc $K8S_PVC_NAME"
echo "2. Pod 상태 확인: kubectl get pod nginx-cephfs"
echo "3. CSI 드라이버 상태: kubectl -n $K8S_CSI_NAMESPACE get pods"