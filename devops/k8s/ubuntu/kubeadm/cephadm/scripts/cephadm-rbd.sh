#!/bin/bash
#=========================================================================
# Ceph RBD 설치 및 Kubernetes CSI 연동 통합 스크립트
# 목적: Ceph RBD 블록 스토리지 설치 및 Kubernetes CSI 드라이버 연동
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

#-------------------------------------------------------------------------
# 1. 설정 변수
#-------------------------------------------------------------------------
# Ceph RBD 기본 설정
export CEPH_POOL_NAME="k8s-rbd-pool"
export CEPH_PG_NUM=128

# Ceph 클라이언트 사용자 설정
export CEPH_CSI_USER="csi-rbd-user"

# Kubernetes 설정
export K8S_CSI_NAMESPACE="ceph-csi-rbd"
export K8S_CSI_RELEASE_NAME="ceph-csi-rbd"
export K8S_SECRET_NAME="csi-rbd-secret"
export K8S_STORAGE_CLASS_NAME="ceph-rbd-sc"
export K8S_PVC_NAME="test-rbd-pvc"
export K8S_TEST_POD_NAME="rbd-test-pod"

#=========================================================================
# 2. Ceph RBD 풀 생성
#=========================================================================
echo -e "\n[단계 1/7] Ceph RBD 풀 생성을 시작합니다..."

#-------------------------------------------------------------------------
# 2.1 RBD 풀 생성 및 초기화
#-------------------------------------------------------------------------
echo ">> RBD 풀 '$CEPH_POOL_NAME' 생성 중..."
ceph osd pool create "$CEPH_POOL_NAME" "$CEPH_PG_NUM" replicated
ceph osd pool application enable "$CEPH_POOL_NAME" rbd
rbd pool init "$CEPH_POOL_NAME"
echo ">> RBD 풀 생성 완료"

# 풀 상태 확인
echo ">> RBD 풀 상태 확인:"
ceph osd pool ls | grep "$CEPH_POOL_NAME"
echo "[단계 1/7] Ceph RBD 풀 생성 완료"

#=========================================================================
# 3. CSI 사용자 생성 및 클러스터 정보 수집
#=========================================================================
echo -e "\n[단계 2/7] CSI 사용자 생성 및 클러스터 정보 수집을 시작합니다..."

#-------------------------------------------------------------------------
# 3.1 CSI 클라이언트 사용자 생성
#-------------------------------------------------------------------------
echo ">> Ceph 사용자 'client.$CEPH_CSI_USER' 생성 및 권한 부여 중..."
ceph auth add client.$CEPH_CSI_USER \
  mon 'profile rbd' \
  osd "profile rbd pool=$CEPH_POOL_NAME" \
  mgr "profile rbd pool=$CEPH_POOL_NAME"
echo ">> 사용자 생성 완료"

#-------------------------------------------------------------------------
# 3.2 사용자 키링 및 클러스터 정보 수집
#-------------------------------------------------------------------------
echo ">> Ceph 사용자 키링 및 클러스터 정보 수집 중..."
# 키링 가져오기
CEPH_USER_KEYRING=$(ceph auth get-key client.$CEPH_CSI_USER)

# 클러스터 ID 가져오기
CEPH_CLUSTER_ID=$(ceph fsid)

# 모니터 주소 목록 가져오기 (v1 Port 6789)
CEPH_MONITOR_IPS=$(ceph mon dump 2>/dev/null | grep -oE 'v1:[0-9.]+:6789' | sed 's/v1://' | tr '\n' ',' | sed 's/,$//')

# 수집된 정보 확인
echo ">> 수집된 Ceph 클러스터 정보:"
echo "   - Cluster ID: $CEPH_CLUSTER_ID"
echo "   - Monitor IPs: $CEPH_MONITOR_IPS"
echo "   - User Keyring (client.$CEPH_CSI_USER): *****" # 보안상 키링 값은 마스킹 처리
echo "[단계 2/7] CSI 사용자 생성 및 클러스터 정보 수집 완료"

#=========================================================================
# 4. Kubernetes ConfigMap 및 Secret 생성
#=========================================================================
echo -e "\n[단계 3/7] Kubernetes ConfigMap 및 Secret 생성을 시작합니다..."

# 네임스페이스 생성
echo ">> Kubernetes 네임스페이스 생성 중..."
kubectl create namespace $K8S_CSI_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# ConfigMap 생성 (CSI 설정)
echo ">> ConfigMap 'ceph-csi-config' 생성 중..."

# 모니터 주소를 JSON 배열 형식으로 변환
MONITOR_JSON_ARRAY=$(echo "$CEPH_MONITOR_IPS" | tr ',' '\n' | sed 's/^/          "/; s/$/",/' | sed '$ s/,$//')

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-csi-config
  namespace: $K8S_CSI_NAMESPACE
data:
  config.json: |-
    [
      {
        "clusterID": "$CEPH_CLUSTER_ID",
        "monitors": [
${MONITOR_JSON_ARRAY}
        ]
      }
    ]
EOF

# KMS ConfigMap 생성 (최신 CSI 버전에서 필요)
echo ">> ConfigMap 'ceph-csi-kms-config' 생성 중..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-csi-kms-config
  namespace: $K8S_CSI_NAMESPACE
data:
  config.json: |-
    {}
EOF

# Secret 생성
echo ">> Kubernetes Secret 생성 중..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $K8S_SECRET_NAME
  namespace: $K8S_CSI_NAMESPACE
type: kubernetes.io/ceph
stringData:
  userID: $CEPH_CSI_USER
  userKey: $CEPH_USER_KEYRING
EOF
echo "[단계 3/7] Kubernetes ConfigMap 및 Secret 생성 완료"

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
# 5.3 Ceph CSI RBD values.yaml 생성
#-------------------------------------------------------------------------
echo ">> Ceph CSI RBD values.yaml 파일 생성 중..."

# 모니터 주소를 YAML 리스트 형식으로 변환
MONITOR_LIST=$(echo "$CEPH_MONITOR_IPS" | tr ',' '\n' | sed 's/^/      - /; s/$//')

cat > rbd-csi-values.yaml << EOF
csiConfig:
  - clusterID: "$CEPH_CLUSTER_ID"
    monitors:
${MONITOR_LIST}

commonLabels:
  app.kubernetes.io/name: "ceph-csi-rbd"
  app.kubernetes.io/managed-by: "helm"

provisioner:
  replicaCount: 2
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 128Mi

nodeplugin:
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 128Mi

storageClass:
  create: false  # StorageClass는 별도로 생성
EOF
echo ">> values.yaml 파일 생성 완료: rbd-csi-values.yaml"

#-------------------------------------------------------------------------
# 5.4 Helm으로 Ceph CSI RBD 드라이버 설치
#-------------------------------------------------------------------------
echo ">> Helm을 사용하여 Ceph CSI RBD 드라이버 설치 중..."
# 기존 ConfigMap 삭제
kubectl delete configmap ceph-csi-config -n "$K8S_CSI_NAMESPACE"
kubectl delete configmap ceph-csi-kms-config -n "$K8S_CSI_NAMESPACE" --ignore-not-found=true

helm upgrade --install "$K8S_CSI_RELEASE_NAME" ceph-csi/ceph-csi-rbd \
  --namespace "$K8S_CSI_NAMESPACE" \
  --values rbd-csi-values.yaml \
  --version 3.9.0
echo ">> Ceph CSI 드라이버 설치 명령 실행 완료"

# CSI 드라이버 배포 대기
echo ">> CSI 드라이버 배포 대기 중..."
kubectl wait --for=condition=ready pod -l app=ceph-csi-rbd -n "$K8S_CSI_NAMESPACE" --timeout=300s || true

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
cat << EOF > rbd-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $K8S_STORAGE_CLASS_NAME
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: "$CEPH_CLUSTER_ID"
  pool: "$CEPH_POOL_NAME"
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: "$K8S_SECRET_NAME"
  csi.storage.k8s.io/provisioner-secret-namespace: "$K8S_CSI_NAMESPACE"
  csi.storage.k8s.io/controller-expand-secret-name: "$K8S_SECRET_NAME"
  csi.storage.k8s.io/controller-expand-secret-namespace: "$K8S_CSI_NAMESPACE"
  csi.storage.k8s.io/node-stage-secret-name: "$K8S_SECRET_NAME"
  csi.storage.k8s.io/node-stage-secret-namespace: "$K8S_CSI_NAMESPACE"
reclaimPolicy: Delete
allowVolumeExpansion: true
mountOptions:
  - discard
EOF

cat << EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $K8S_STORAGE_CLASS_NAME
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: "$CEPH_CLUSTER_ID"
  pool: "$CEPH_POOL_NAME"
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: "$K8S_SECRET_NAME"
  csi.storage.k8s.io/provisioner-secret-namespace: "$K8S_CSI_NAMESPACE"
  csi.storage.k8s.io/controller-expand-secret-name: "$K8S_SECRET_NAME"
  csi.storage.k8s.io/controller-expand-secret-namespace: "$K8S_CSI_NAMESPACE"
  csi.storage.k8s.io/node-stage-secret-name: "$K8S_SECRET_NAME"
  csi.storage.k8s.io/node-stage-secret-namespace: "$K8S_CSI_NAMESPACE"
reclaimPolicy: Delete
allowVolumeExpansion: true
mountOptions:
  - discard
EOF
echo ">> StorageClass YAML 파일 생성 완료: rbd-storageclass.yaml"

# StorageClass 생성
echo ">> StorageClass 생성 중..."
kubectl apply -f rbd-storageclass.yaml
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
cat << EOF > rbd-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $K8S_PVC_NAME
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: "$K8S_STORAGE_CLASS_NAME"
EOF
echo ">> PVC YAML 파일 생성 완료: rbd-pvc.yaml"

# PVC 생성
echo ">> PVC 생성 중..."
kubectl apply -f rbd-pvc.yaml
echo ">> PVC 생성 완료"

# PVC 상태 확인
echo ">> PVC 상태 확인 (Bound 상태 대기)..."
kubectl wait --for=condition=Bound pvc/"$K8S_PVC_NAME" --timeout=60s || true
kubectl get pvc "$K8S_PVC_NAME"
echo "[단계 6/7] PersistentVolumeClaim 생성 완료"

#=========================================================================
# 8. 테스트 Pod 생성
#=========================================================================
echo -e "\n[단계 7/7] 테스트 Pod 생성을 시작합니다..."

# 테스트 Pod YAML 파일 생성
echo ">> 테스트 Pod YAML 파일 생성 중..."
cat << EOF > rbd-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: $K8S_TEST_POD_NAME
spec:
  containers:
  - name: test-app
    image: nginx:alpine
    volumeMounts:
    - name: rbd-storage
      mountPath: /var/www/html
    command: ["/bin/sh"]
    args: 
    - "-c"
    - |
      echo "RBD Storage Test File" > /var/www/html/index.html
      echo "Storage mounted successfully at $(date)" >> /var/www/html/mount.log
      nginx -g 'daemon off;'
  volumes:
  - name: rbd-storage
    persistentVolumeClaim:
      claimName: "$K8S_PVC_NAME"
EOF
echo ">> 테스트 Pod YAML 파일 생성 완료: rbd-test-pod.yaml"

# 테스트 Pod 생성
echo ">> 테스트 Pod 생성 중..."
kubectl apply -f rbd-test-pod.yaml
echo ">> 테스트 Pod 생성 완료"

# 테스트 Pod 상태 확인
echo ">> 테스트 Pod 상태 확인:"
kubectl wait --for=condition=Ready pod/"$K8S_TEST_POD_NAME" --timeout=60s || true
kubectl get pod "$K8S_TEST_POD_NAME"
echo "[단계 7/7] 테스트 Pod 생성 완료"

#=========================================================================
# 9. 설치 완료 및 검증 안내
#=========================================================================
echo -e "\n[완료] Ceph RBD 및 Kubernetes CSI 연동 설치가 완료되었습니다."
echo -e "\n===== 설치 검증 방법 ====="
echo "1. PVC 상태 확인 (Bound 상태여야 함):"
echo "   kubectl get pvc $K8S_PVC_NAME"
echo ""
echo "2. Pod 상태 확인 (Running 상태여야 함):"
echo "   kubectl get pod $K8S_TEST_POD_NAME"
echo ""
echo "3. 스토리지 마운트 확인:"
echo "   kubectl exec $K8S_TEST_POD_NAME -- df -h | grep rbd"
echo ""
echo "4. 테스트 파일 확인:"
echo "   kubectl exec $K8S_TEST_POD_NAME -- cat /var/www/html/index.html"
echo "   kubectl exec $K8S_TEST_POD_NAME -- cat /var/www/html/mount.log"
echo ""
echo "5. Ceph RBD 이미지 확인:"
echo "   rbd ls -p $CEPH_POOL_NAME"
echo ""
echo "===== 리소스 정리 방법 ====="
echo "1. 테스트 리소스 삭제:"
echo "   kubectl delete -f rbd-test-pod.yaml"
echo "   kubectl delete -f rbd-pvc.yaml"
echo "   kubectl delete -f rbd-storageclass.yaml"
echo ""
echo "2. CSI 드라이버 제거:"
echo "   helm uninstall $K8S_CSI_RELEASE_NAME -n $K8S_CSI_NAMESPACE"
echo "   kubectl delete namespace $K8S_CSI_NAMESPACE"
echo ""
echo "3. Ceph 사용자 제거:"
echo "   ceph auth del client.$CEPH_CSI_USER"
echo ""
echo "4. RBD 풀 제거 (주의: 모든 데이터가 삭제됩니다):"
echo "   ceph osd pool rm $CEPH_POOL_NAME $CEPH_POOL_NAME --yes-i-really-really-mean-it"
echo ""
echo "===== 로그 확인 방법 ====="
echo "CSI 드라이버 이슈:"
echo "   kubectl logs -n $K8S_CSI_NAMESPACE -l app=ceph-csi-rbd"
echo ""
echo "Ceph 클러스터 상태:"
echo "   ceph -s"
echo "   ceph health detail"