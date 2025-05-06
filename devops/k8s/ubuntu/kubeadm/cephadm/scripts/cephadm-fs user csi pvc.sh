#!/bin/bash
set -e

# CephFS 설치를 위한 변수 설정 (필요에 따라 수정하세요)
FS_NAME="mycephfs" # 생성할 파일 시스템 이름 [previous response, 48]
METADATA_POOL="${FS_NAME}_metadata"
DATA_POOL="${FS_NAME}_data"
MDS_COUNT=2 # 배포할 MDS 데몬 수 [previous response]
MDS_HOSTS="k8s-worker-1 k8s-worker-2" # 호스트 이름은 'ceph orch host ls' 명령으로 확인 가능
CEPH_CSI_USER="ceph-csi-user" # CSI 드라이버가 사용할 Ceph 클라이언트 사용자 ID (client. 접두사는 자동으로 붙음)
K8S_CSI_NAMESPACE="ceph-csi-cephfs" # CSI 드라이버를 배포할 Kubernetes 네임스페이스
K8S_CSI_RELEASE_NAME="ceph-csi-cephfs-release" # Helm 릴리스 이름
K8S_SECRET_NAME="ceph-csi-cephfs-keyring" # Ceph 키링을 저장할 Kubernetes Secret 이름
K8S_STORAGE_CLASS_NAME="cephfs-sc" # 생성할 Kubernetes StorageClass 이름
K8S_PVC_NAME="my-cephfs-pvc" # 생성할 PersistentVolumeClaim 이름
K8S_TEST_POD_NAME="cephfs-test-pod" # 생성할 테스트 Pod 이름

# 확보할 Ceph 클러스터 정보 변수
CEPH_CLUSTER_ID=""
CEPH_MONITOR_IPS=""
CEPH_USER_KEYRING=""

echo "CephFS 클라이언트 설정 및 Kubernetes 연동 스크립트를 시작합니다."

# --- 1. CephFS 클라이언트 사용자 생성 및 키링 확보 (cephadm 쉘 내부) ---
echo "Cephadm 쉘에 접근하여 CephFS 클라이언트 사용자 '$CEPH_CSI_USER'를 생성하고 키링을 가져옵니다..."
# Cephadm 쉘 실행 및 명령 수행
echo "Ceph 사용자 '$CEPH_CSI_USER' 생성 및 권한 부여..."
# CephFS 사용을 위한 권한 부여 (mon, mds, osd, mgr 접근)
# OSD 권한은 데이터 풀에 대해 부여하는 것이 일반적이지만, 여기서는 모든 풀에 대한 읽기/쓰기 권한 예시
# 실제 환경에서는 필요한 최소 권한만 부여하는 것이 보안상 좋습니다.
ceph auth add client.$CEPH_CSI_USER mds 'allow *' mon 'allow *' osd 'allow *' mgr 'allow *'

echo "Ceph 사용자 '$CEPH_CSI_USER'의 키링 확보..."
# 키링 내용을 가져와서 변수에 저장
CEPH_USER_KEYRING=$(ceph auth get-key client.$CEPH_CSI_USER)
echo "CEPH_USER_KEYRING: $CEPH_USER_KEYRING"

echo "Ceph 클러스터 정보 확보 (Cluster ID, 모니터 주소)..."
# Cluster ID 확보
CEPH_CLUSTER_ID=$(ceph fsid)
echo "CEPH_CLUSTER_ID: $CEPH_CLUSTER_ID"

# 모니터 주소 목록 확보 (콤마로 구분된 IP:Port 형식)
# 'ceph mon dump' 명령 결과 파싱
# 실제 환경에서는 네트워크 구성에 따라 접근 가능한 IP 및 포트를 확인해야 합니다.
CEPH_MONITOR_IPS=$(ceph mon dump | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:3300' | tr '\n' ',' | sed 's/,$//')
echo "CEPH_MONITOR_IPS: $CEPH_MONITOR_IPS"

# Cephadm 쉘 실행 결과 파싱하여 변수에 저장
echo "실행 결과를 파싱합니다."
echo "Ceph Cluster ID: $CEPH_CLUSTER_ID"
echo "Ceph Monitor IPs: $CEPH_MONITOR_IPS"
echo "Ceph User Keyring (client.$CEPH_CSI_USER): $CEPH_USER_KEYRING"

# --- 2. Kubernetes Secret 생성 준비 ---
echo ""
echo "--- Kubernetes Secret 생성 ---"
echo "확보한 Ceph 사용자 키링을 사용하여 Kubernetes Secret을 생성해야 합니다."
echo "CSI 드라이버는 이 Secret을 통해 Ceph 클러스터에 인증합니다."
echo "아래 YAML 템플릿을 복사하여 파일로 저장하고, 'kubectl apply -f <secret-file>.yaml -n $K8S_CSI_NAMESPACE' 명령으로 Secret을 생성하세요."
# Create the YAML file with variable substitution


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
kubectl create namespace $K8S_CSI_NAMESPACE
kubectl apply -f ceph-secret.yaml -n $K8S_CSI_NAMESPACE

# --- 3. Ceph CSI Helm 저장소 추가 및 업데이트 ---
echo "Ceph CSI Helm 저장소를 추가하고 업데이트합니다..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
helm repo add ceph-csi https://ceph.github.io/csi-charts
helm repo update

# --- 4. Ceph CSI 드라이버 설치 ---
echo "Ceph CSI FS Helm 차트 설치를 위한 values.yaml 파일을 생성합니다..."
# values.yaml 파일 내용 정의
cat << EOF > cephfs-csi-values.yaml
csiConfig:
  - clusterID: "$CEPH_CLUSTER_ID" # Ceph 클러스터의 고유 ID
    monitors: # Ceph 모니터 주소 목록
$(echo "$CEPH_MONITOR_IPS" | tr ',' '\n' | sed 's/^/    - /') # 문자열을 YAML 목록 형식으로 변환
secrets:
  - name: "$K8S_SECRET_NAME" # Kubernetes Secret 이름
provisioner:
  # StorageClass에서 사용할 CephFS 파일 시스템 이름
  # 이 값은 StorageClass 정의에도 필요합니다.
  fsName: "$FS_NAME"
EOF
echo "values.yaml 파일이 생성되었습니다. 내용을 확인/수정하세요: cephfs-csi-values.yaml"

echo "Helm을 사용하여 Ceph CSI FS 드라이버를 설치합니다..."
helm install --namespace "$K8S_CSI_NAMESPACE" "$K8S_CSI_RELEASE_NAME" ceph-csi/ceph-csi-cephfs -f cephfs-csi-values.yaml --version 3.9.0 # 최신 버전 확인 후 사용 권장 (예: 3.9.0)

echo "CSI 드라이버 배포 상태를 확인합니다..."
helm status "$K8S_CSI_RELEASE_NAME" -n "$K8S_CSI_NAMESPACE"
kubectl get pods -n "$K8S_CSI_NAMESPACE" # 모든 파드가 Running 상태가 될 때까지 대기하거나 확인

WAIT_TIME=120
echo "CSI 드라이버 배포를 위해 ${WAIT_TIME}초 대기합니다..."
# 카운터 초기화
counter=0
while [ $counter -lt $WAIT_TIME ]; do
  # 화면 지우기 없이 경과 시간만 업데이트
  echo -ne "CSI 드라이버 배포를 위해 ${WAIT_TIME}초 대기합니다...(경과시간: ${counter}초)\r"
  sleep 1
  counter=$((counter + 1))
done
echo -e "CSI 드라이버 배포를 위해 ${WAIT_TIME}초 대기합니다...(경과시간: ${WAIT_TIME}초) - 완료"

# --- 5. Kubernetes StorageClass 생성 ---
echo "CephFS 볼륨 동적 프로비저닝을 위한 StorageClass를 생성합니다..."
# StorageClass YAML 내용 정의
cat << EOF > cephfs-storageclass.yaml
# 이 파일은 CephFS StorageClass 정의를 담고 있습니다.
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $K8S_STORAGE_CLASS_NAME
provisioner: cephfs.csi.ceph.com # CephFS CSI 드라이버 프로비저너
parameters:
  clusterID: "$CEPH_CLUSTER_ID" # CSI 드라이버의 clusterID와 일치해야 함
  fsName: "$FS_NAME" # 사용할 CephFS 파일 시스템 이름
  pool: "$DATA_POOL" # 데이터 풀 지정 (생략 시 파일 시스템의 기본 데이터 풀 사용)
  # CSI Secret 이름을 지정하여 인증 정보를 참조
  csi.storage.k8s.io/provisioner-secret-name: "$K8S_SECRET_NAME"
  csi.storage.k8s.io/provisioner-secret-namespace: "$K8S_CSI_NAMESPACE"
  csi.storage.k8s.io/node-stage-secret-name: "$K8S_SECRET_NAME"
  csi.storage.k8s.io/node-stage-secret-namespace: "$K8S_CSI_NAMESPACE"
reclaimPolicy: Delete # PV 삭제 시 데이터도 삭제 (Retain 가능)
allowVolumeExpansion: true # 볼륨 확장 허용 여부
mountOptions: # 마운트 옵션 (선택 사항)
  - debug
EOF

echo "StorageClass YAML 파일이 생성되었습니다: cephfs-storageclass.yaml"
kubectl apply -f cephfs-storageclass.yaml

echo "StorageClass 생성 상태를 확인합니다..."
kubectl get storageclass "$K8S_STORAGE_CLASS_NAME"

# --- 6. PersistentVolumeClaim (PVC) 생성 ---
echo "CephFS 볼륨을 요청하는 PersistentVolumeClaim (PVC)을 생성합니다..."
# PVC YAML 내용 정의
cat << EOF > cephfs-pvc.yaml
# 이 파일은 CephFS PersistentVolumeClaim 정의를 담고 있습니다.
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

echo "PVC YAML 파일이 생성되었습니다: cephfs-pvc.yaml"
kubectl apply -f cephfs-pvc.yaml

echo "PVC 생성 상태를 확인합니다..."
kubectl get pvc "$K8S_PVC_NAME"

# --- 7. 테스트 Pod 생성 ---
echo "생성된 PVC를 사용하는 테스트 Pod를 생성합니다..."
# Test Pod YAML 내용 정의
cat << EOF > cephfs-test-pod.yaml
# 이 파일은 CephFS PersistentVolumeClaim을 사용하는 테스트 Pod 정의를 담고 있습니다.
apiVersion: v1
kind: Pod
metadata:
  name: $K8S_TEST_POD_NAME
  # namespace: default # 기본 네임스페이스 사용 또는 지정
spec:
  containers:
  - name: test-container
    image: ubuntu # 또는 다른 테스트 이미지 (nginx 등)
    command: ['sh', '-c', 'echo "Hello, CephFS from Kubernetes!" > /mnt/cephfs/hello.txt && sleep 3600'] # 볼륨에 파일 생성 테스트
    volumeMounts:
    - name: cephfs-storage # Pod 내부 볼륨 마운트 이름
      mountPath: /mnt/cephfs # 볼륨을 마운트할 경로
  volumes:
  - name: cephfs-storage # Pod 내부 볼륨 이름
    persistentVolumeClaim:
      claimName: "$K8S_PVC_NAME" # 사용할 PVC 이름
      readOnly: false # 읽기/쓰기 가능 설정
EOF

echo "테스트 Pod YAML 파일이 생성되었습니다: cephfs-test-pod.yaml"
kubectl apply -f cephfs-test-pod.yaml

echo "테스트 Pod 생성 상태를 확인합니다..."
kubectl get pod "$K8S_TEST_POD_NAME"

echo ""
echo "--- CephFS Kubernetes 연동 및 테스트 Pod 배포 프로세스 완료 ---"
echo "kubectl get pvc $K8S_PVC_NAME 로 PVC 상태를 확인하세요 (Bound 상태가 되어야 합니다)."
echo "kubectl get pod $K8S_TEST_POD_NAME 로 Pod 상태를 확인하세요 (Running 상태가 되어야 합니다)."
echo "Pod가 Running 상태가 되면 'kubectl exec $K8S_TEST_POD_NAME -- cat /mnt/cephfs/hello.txt' 명령으로 파일 생성 결과를 확인해 보세요."
echo "여러 개의 Pod를 생성하여 동일한 PVC를 마운트하고 파일 공유를 테스트할 수도 있습니다."

echo "클린업: 테스트를 마친 후 'kubectl delete -f cephfs-test-pod.yaml,cephfs-pvc.yaml,cephfs-storageclass.yaml' 명령으로 생성한 리소스를 삭제할 수 있습니다."
echo "CSI 드라이버를 제거하려면 'helm uninstall $K8S_CSI_RELEASE_NAME -n $K8S_CSI_NAMESPACE && kubectl delete namespace $K8S_CSI_NAMESPACE' 명령을 사용하세요."
echo "Ceph 사용자를 제거하려면 Cephadm 쉘에서 'ceph auth del client.$CEPH_CSI_USER' 명령을 사용하세요."