#!/bin/bash

# --- 전역 변수 설정 (환경에 맞게 수정 필요) ---
CEPH_MON_IP="<Ceph 모니터 IP 주소>" # 예: 10.0.0.136 [이전 대화 참고]
CEPH_FSID="<Ceph 클러스터 FSID>"    # 예: a1b2c3d4-e5f6-7890-1234-567890abcdef [이전 대화 참고]
CEPH_POOL_NAME="k8s-rbd-pool"      # Kubernetes에서 사용할 Ceph 풀 이름
CEPH_USER_NAME="client.kubernetes" # Kubernetes CSI가 사용할 Ceph 사용자 이름
CEPH_USER_KEY="<ceph auth get-or-create 명령으로 얻은 사용자 키>" # 예: AQB...== [이전 대화 참고]
K8S_NAMESPACE="default"           # K8s 객체를 생성할 네임스페이스 (StorageClass, Secret 등)
TEST_PVC_NAME="ceph-rbd-pvc"     # 테스트 PVC 이름
TEST_POD_NAME="ceph-rbd-test-pod" # 테스트 Pod 이름
CEPH_CSI_HELM_VERSION="<설치할 ceph-csi Helm 차트 버전>" # 예: 3.7.1 (helm search repo ceph-csi/ceph-csi-rbd 로 확인)

# --- 2. Kubernetes에서 사용할 Ceph 풀 및 사용자 설정 ---

echo "Ceph 풀 '$CEPH_POOL_NAME' 생성 및 초기화..."
# Ceph CLI가 설치된 노드 또는 cephadm shell 에서 실행 [이전 대화 참고]
ceph osd pool create $CEPH_POOL_NAME 128 128 # 풀 생성 (PG 수 조정 필요) [이전 대화 참고]
if [ $? -ne 0 ]; then echo "Ceph 풀 생성 실패. 스크립트 중단."; exit 1; fi
rbd pool init $CEPH_POOL_NAME             # RBD 풀 초기화 [이전 대화 참고]
if [ $? -ne 0 ]; then echo "RBD 풀 초기화 실패. 스크립트 중단."; exit 1; fi
echo "Ceph 풀 '$CEPH_POOL_NAME' 생성 및 초기화 완료."

echo "Kubernetes용 Ceph 사용자 '$CEPH_USER_NAME' 생성 및 키 확인..."
# Cephx 사용자 생성 [이전 대화 참고]
# 생성된 키는 CEPH_USER_KEY 변수에 수동으로 입력하거나, 안전한 방법으로 추출해야 함
ceph auth add client.$CEPH_CSI_USER \
  mon 'profile rbd' \
  osd 'profile rbd pool='"$CEPH_POOL_NAME" \
  mgr 'profile rbd pool='"$CEPH_POOL_NAME"

if [ $? -ne 0 ]; then echo "Ceph 사용자 생성 실패. 스크립트 중단."; exit 1; fi
echo "Ceph 사용자 '$CEPH_USER_NAME' 생성 확인."
echo "CEPH_USER_KEY 변수에 사용자 키를 정확히 입력했는지 확인하십시오."

# --- 3. Ceph-CSI 드라이버 설치 준비 (ConfigMap, Secret) ---

echo "Kubernetes ConfigMap 및 Secret 생성 준비..."

# Ceph CSI ConfigMap (clusterID, monitors) 생성 [이전 대화 참고]
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
data:
  config.json: |-
    [
      {
        "clusterID": "$CEPH_FSID",
        "monitors": [
          "$CEPH_MON_IP:6789" # v1 프로토콜 기본 포트 6789 [이전 대화 참고]
        ]
      }
    ]
metadata:
  name: ceph-csi-config
  namespace: $K8S_NAMESPACE
EOF
if [ $? -ne 0 ]; then echo "ConfigMap 생성 실패. 스크립트 중단."; exit 1; fi
echo "ConfigMap 'ceph-csi-config' 생성 완료."

# 최신 ceph-csi는 KMS ConfigMap 요구 가능 (비어있어도 됨) [이전 대화 참고]
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
data:
  config.json: |-
    {}
metadata:
  name: ceph-csi-kms-config
  namespace: $K8S_NAMESPACE
EOF
if [ $? -ne 0 ]; then echo "KMS ConfigMap 생성 실패. 스크립트 중단."; exit 1; fi
echo "ConfigMap 'ceph-csi-kms-config' 생성 완료."

# Cephx Secret 생성 [이전 대화 참고]
# CEPH_USER_KEY는 base64로 인코딩하여 Secret에 저장해야 합니다.
# 이 예제에서는 평문 키를 echo 후 base64 인코딩합니다. 실제 환경에서는 보안 고려 필요.
CEPH_USER_KEY_BASE64=$(echo -n "$CEPH_USER_KEY" | base64 -w 0)

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: csi-rbd-secret
  namespace: $K8S_NAMESPACE
type: kubernetes.io/ceph
data:
  userID: $(echo -n "$CEPH_USER_NAME" | base64 -w 0)
  userKey: $CEPH_USER_KEY_BASE64
EOF
if [ $? -ne 0 ]; then echo "Secret 'csi-rbd-secret' 생성 실패. 스크립트 중단."; exit 1; fi
echo "Secret 'csi-rbd-secret' 생성 완료."

# --- 4. Ceph-CSI 드라이버 Helm 차트 설치 ---

echo "Helm Repository 추가 및 업데이트..."
helm repo add ceph-csi https://ceph.github.io/csi-charts
if [ $? -ne 0 ]; then echo "Helm Repo 추가 실패. 스크립트 중단."; exit 1; fi
helm repo update
if [ $? -ne 0 ]; then echo "Helm Repo 업데이트 실패. 스크립트 중단."; exit 1; fi
echo "Helm Repo 추가 및 업데이트 완료."

echo "Ceph-CSI RBD Helm 차트 설치..."
# values.yaml 파일로 추가 설정 가능 [14], 예시에서는 필수 값만 인자로 전달
helm install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
  --namespace $K8S_NAMESPACE --create-namespace \
  --version $CEPH_CSI_HELM_VERSION \
  --set configMapName=ceph-csi-config \
  --set csiConfigBase64=$(echo -n "[{\"clusterID\": \"$CEPH_FSID\", \"monitors\": [\"$CEPH_MON_IP:6789\"]}]" | base64 -w 0) \
  --set enableRbd=true
# 추가 설정이 필요하다면 --values <your-values.yaml> 사용

if [ $? -ne 0 ]; then echo "Ceph-CSI Helm 차트 설치 실패. 스크립트 중단."; exit 1; fi
echo "Ceph-CSI RBD Helm 차트 설치 완료."
echo "kubectl get pods -n $K8S_NAMESPACE | grep csi 로 CSI Pod 상태 확인"


# --- 5. StorageClass, PVC, 테스트 Pod 생성 ---

echo "Kubernetes StorageClass 생성..."
# StorageClass 정의 [이전 대화 참고]
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-rbd-sc
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: "$CEPH_FSID"
  pool: "$CEPH_POOL_NAME"
  imageFeatures: "layering" # 필요한 RBD 기능 활성화 [15, 16]
  csi.storage.k8s.io/provisioner-secret-name: csi-rbd-secret
  csi.storage.k8s.io/provisioner-secret-namespace: $K8S_NAMESPACE
  csi.storage.k8s.io/controller-expand-secret-name: csi-rbd-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: $K8S_NAMESPACE
  csi.storage.k8s.io/node-stage-secret-name: csi-rbd-secret
  csi.storage.k8s.io/node-stage-secret-namespace: $K8S_NAMESPACE
reclaimPolicy: Delete # PersistentVolumeClaim 삭제 시 RBD 이미지도 삭제 [이전 대화 참고]
allowVolumeExpansion: true
mountOptions:
  - discard # 디스카드 옵션 활성화 (성능 향상) [19, 이전 대화 참고]
EOF
if [ $? -ne 0 ]; then echo "StorageClass 생성 실패. 스크립트 중단."; exit 1; fi
echo "StorageClass 'csi-rbd-sc' 생성 완료."

echo "Kubernetes PersistentVolumeClaim (PVC) 생성..."
# 테스트용 PVC 정의 [6]
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $TEST_PVC_NAME
  namespace: $K8S_NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce # 한 번에 하나의 Pod만 ReadWrite로 마운트 [6]
  resources:
    requests:
      storage: 1Gi # 요청 스토리지 용량 (필요에 따라 조정)
  storageClassName: csi-rbd-sc # 위에서 생성한 StorageClass 이름
EOF
if [ $? -ne 0 ]; then echo "PVC 생성 실패. 스크립트 중단."; exit 1; fi
echo "PVC '$TEST_PVC_NAME' 생성 완료."
echo "kubectl get pvc -n $K8S_NAMESPACE 에서 상태 확인 (Pending -> Bound)."

# PVC 상태가 Bound가 될 때까지 기다리는 로직 추가 필요 (선택 사항)
# kubectl wait --for=condition=Bound pvc $TEST_PVC_NAME -n $K8S_NAMESPACE --timeout=300s

echo "테스트 Pod 생성 (PVC 마운트 확인)..."
# PVC를 사용하는 테스트 Pod 정의 [6]
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $TEST_POD_NAME
  namespace: $K8S_NAMESPACE
spec:
  containers:
  - name: test-container
    image: busybox # 가벼운 테스트 이미지
    command: [ "/bin/sh", "-c", "while true; do echo $(date -u) >> /data/test.log; sleep 5; done" ] # 간단한 파일 쓰기 테스트
    volumeMounts:
    - name: persistent-storage
      mountPath: /data # PVC를 마운트할 경로
  volumes:
  - name: persistent-storage
    persistentVolumeClaim:
      claimName: $TEST_PVC_NAME # 사용할 PVC 이름
EOF
if [ $? -ne 0 ]; then echo "테스트 Pod 생성 실패. 스크립트 중단."; exit 1; fi
echo "테스트 Pod '$TEST_POD_NAME' 생성 완료."
echo "kubectl get pods -n $K8S_NAMESPACE | grep $TEST_POD_NAME 에서 상태 확인."
echo "Pod가 Running 상태가 되면 kubectl exec -it $TEST_POD_NAME -n $K8S_NAMESPACE -- cat /data/test.log 로 쓰기 테스트 확인."

echo "스크립트 실행 완료."