#!/bin/bash
# Phase 5: CSI 연동 — Ceph CSI (Helm) + BeeGFS CSI (kustomize)
# 실행: EC2 #1 (frontend) 에서 실행
# 사전 조건:
#   - kubectl 사용 가능 (kubeconfig 설정 완료)
#   - BACKEND_PRIVATE_IP 환경변수 설정 (EC2 #2 Private IP)
#   - CEPH_FSID, CEPH_ADMIN_KEY 환경변수 설정
set -e

export KUBECONFIG="${HOME}/.kube/config"

# start.sh에서 ~/04_csi_install.sh로 실행될 때 manifests는 ~/manifests에 있음
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST_DIR="${SCRIPT_DIR}/manifests"

: "${BACKEND_PRIVATE_IP:?필수: export BACKEND_PRIVATE_IP=<EC2#2 Private IP>}"
: "${CEPH_FSID:?필수: export CEPH_FSID=<ceph fsid>}"
: "${CEPH_ADMIN_KEY:?필수: export CEPH_ADMIN_KEY=<ceph auth get-key client.admin>}"

echo "=============================="
echo " [1/4] 필수 도구 설치 확인"
echo "=============================="
# git: BeeGFS CSI driver clone 필수
if ! command -v git &>/dev/null; then
  sudo apt-get install -y git -qq
fi

# Helm
if ! command -v helm &>/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm version --short

echo "=============================="
echo " [2/4] Ceph CSI 설치"
echo "=============================="
kubectl create namespace ceph-csi --dry-run=client -o yaml | kubectl apply -f -

# csi-config.yaml 생성 (fsid + mon IP)
cat > "${MANIFEST_DIR}/ceph-csi/csi-config.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ceph-csi-config
  namespace: ceph-csi
data:
  config.json: |
    [
      {
        "clusterID": "${CEPH_FSID}",
        "monitors": ["${BACKEND_PRIVATE_IP}:6789"]
      }
    ]
EOF

# secret-rbd.yaml 생성
cat > "${MANIFEST_DIR}/ceph-csi/secret-rbd.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: csi-rbd-secret
  namespace: ceph-csi
stringData:
  userID: admin
  userKey: ${CEPH_ADMIN_KEY}
EOF

# secret-cephfs.yaml 생성
cat > "${MANIFEST_DIR}/ceph-csi/secret-cephfs.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: csi-cephfs-secret
  namespace: ceph-csi
stringData:
  adminID: admin
  adminKey: ${CEPH_ADMIN_KEY}
EOF

# storageclass-rbd.yaml 생성
cat > "${MANIFEST_DIR}/ceph-csi/storageclass-rbd.yaml" <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-rbd
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: ${CEPH_FSID}
  pool: kubernetes
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: csi-rbd-secret
  csi.storage.k8s.io/provisioner-secret-namespace: ceph-csi
  csi.storage.k8s.io/controller-expand-secret-name: csi-rbd-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: ceph-csi
  csi.storage.k8s.io/node-stage-secret-name: csi-rbd-secret
  csi.storage.k8s.io/node-stage-secret-namespace: ceph-csi
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: Immediate
EOF

# storageclass-cephfs.yaml 생성
cat > "${MANIFEST_DIR}/ceph-csi/storageclass-cephfs.yaml" <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-cephfs
provisioner: cephfs.csi.ceph.com
parameters:
  clusterID: ${CEPH_FSID}
  fsName: cephfs
  csi.storage.k8s.io/provisioner-secret-name: csi-cephfs-secret
  csi.storage.k8s.io/provisioner-secret-namespace: ceph-csi
  csi.storage.k8s.io/controller-expand-secret-name: csi-cephfs-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: ceph-csi
  csi.storage.k8s.io/node-stage-secret-name: csi-cephfs-secret
  csi.storage.k8s.io/node-stage-secret-namespace: ceph-csi
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: Immediate
EOF

kubectl apply -f "${MANIFEST_DIR}/ceph-csi/csi-config.yaml"
kubectl apply -f "${MANIFEST_DIR}/ceph-csi/secret-rbd.yaml"
kubectl apply -f "${MANIFEST_DIR}/ceph-csi/secret-cephfs.yaml"

# Helm이 기존 리소스를 소유할 수 있도록 메타데이터 부여
kubectl annotate configmap ceph-csi-config -n ceph-csi \
  meta.helm.sh/release-name=ceph-csi-rbd \
  meta.helm.sh/release-namespace=ceph-csi --overwrite
kubectl label configmap ceph-csi-config -n ceph-csi \
  app.kubernetes.io/managed-by=Helm --overwrite

helm repo add ceph-csi https://ceph.github.io/csi-charts 2>/dev/null || helm repo update
helm upgrade --install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
  -n ceph-csi \
  --set provisioner.replicaCount=1

for cm in ceph-config ceph-csi-config; do
  kubectl annotate configmap $cm -n ceph-csi \
    meta.helm.sh/release-name=ceph-csi-cephfs \
    meta.helm.sh/release-namespace=ceph-csi --overwrite 2>/dev/null || true
  kubectl label configmap $cm -n ceph-csi \
    app.kubernetes.io/managed-by=Helm --overwrite 2>/dev/null || true
done

helm upgrade --install ceph-csi-cephfs ceph-csi/ceph-csi-cephfs \
  -n ceph-csi \
  --set provisioner.replicaCount=1

kubectl apply -f "${MANIFEST_DIR}/ceph-csi/storageclass-rbd.yaml"
kubectl apply -f "${MANIFEST_DIR}/ceph-csi/storageclass-cephfs.yaml"

echo "Ceph CSI 롤아웃 대기..."
kubectl rollout status deployment/ceph-csi-rbd-provisioner -n ceph-csi --timeout=120s
kubectl rollout status deployment/ceph-csi-cephfs-provisioner -n ceph-csi --timeout=120s

echo "=============================="
echo " [3/4] BeeGFS CSI 설치 (kustomize)"
echo "=============================="
# csi-beegfs-config.yaml 생성 (mgmtd IP 직접 치환)
cat > "${MANIFEST_DIR}/beegfs-csi/csi-beegfs-config.yaml" <<EOF
config:
  beegfsClientConf:
    connDisableAuthentication: "true"
fileSystemSpecificConfigs:
  - sysMgmtdHost: ${BACKEND_PRIVATE_IP}
    config:
      beegfsClientConf:
        connDisableAuthentication: "true"
EOF

# storageclass-beegfs.yaml 생성 (mgmtd IP 직접 치환)
cat > "${MANIFEST_DIR}/beegfs-csi/storageclass-beegfs.yaml" <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: beegfs-scratch
provisioner: beegfs.csi.netapp.com
parameters:
  sysMgmtdHost: ${BACKEND_PRIVATE_IP}
  volDirBasePath: /k8s/dynamic
  beegfsClientConf/connDisableAuthentication: "true"
reclaimPolicy: Delete
volumeBindingMode: Immediate
allowVolumeExpansion: false
EOF

# BeeGFS CSI Driver 클론
if [ ! -d /tmp/beegfs-csi-driver ]; then
  git clone --depth 1 https://github.com/ThinkParQ/beegfs-csi-driver.git /tmp/beegfs-csi-driver
fi

# overlay config 복사
cp "${MANIFEST_DIR}/beegfs-csi/csi-beegfs-config.yaml" \
  /tmp/beegfs-csi-driver/deploy/k8s/overlays/default/csi-beegfs-config.yaml

kubectl apply -k /tmp/beegfs-csi-driver/deploy/k8s/overlays/default

echo "BeeGFS CSI 롤아웃 대기..."
kubectl rollout status statefulset/csi-beegfs-controller -n beegfs-csi --timeout=180s
kubectl rollout status daemonset/csi-beegfs-node -n beegfs-csi --timeout=180s

kubectl apply -f "${MANIFEST_DIR}/beegfs-csi/storageclass-beegfs.yaml"

echo "=============================="
echo " [4/4] 결과 확인"
echo "=============================="
kubectl get storageclass
echo ""
echo "✅ CSI 설치 완료"
echo "   StorageClass: ceph-rbd, ceph-cephfs, beegfs-scratch"
