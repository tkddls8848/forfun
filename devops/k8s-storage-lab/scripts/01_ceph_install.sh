#!/bin/bash
set -e
source scripts/.env

export KUBECONFIG=~/.kube/config-k8s-storage-lab
SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

ROOK_VERSION="v1.13.0"
CEPH_IMAGE="quay.io/ceph/ceph:v18"

echo "=============================="
echo " Step 1: Helm 설치 (master-1)"
echo "=============================="
$CSSH$M1_PUB "
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  helm version
"

echo "=============================="
echo " Step 1-1: rook-ceph Helm repo 추가"
echo "=============================="
$CSSH$M1_PUB "
  helm repo add rook-release https://charts.rook.io/release
  helm repo update
  kubectl create namespace rook-ceph || true
"

echo "=============================="
echo " Step 1-2: rook-ceph Operator 배포"
echo "=============================="
$CSSH$M1_PUB "helm upgrade --install rook-ceph rook-release/rook-ceph --namespace rook-ceph --version $ROOK_VERSION"
echo "  Operator Pod 기동 대기..."
$CSSH$M1_PUB "kubectl -n rook-ceph rollout status deployment/rook-ceph-operator --timeout=300s"

# [안정화 대기 1] operator의 CRD watch 연결(20+개)이 안정화될 시간 확보
# 바로 CephCluster를 배포하면 watch 폭풍 + reconcile 루프로 etcd 과부하 발생
echo "  CRD watch 안정화 대기 (60초)..."
sleep 60
$CSSH$M1_PUB "kubectl -n rook-ceph get pods"

echo "=============================="
echo " Step 1-3: CephCluster CR 배포 (HCI: worker-1~4)"
echo "=============================="
# mon count=1 (실습 환경 최적화)
# - mon 3개: mon pod × 3 + mgr + OSD × 8 + CSI × 12 → API server 과부하
# - mon 1개: API server 연결 수 대폭 감소, 단일 master 환경에 적합
# - replication size=2로 조정 (mon 1개에서 size=3은 PG undersized 경고 발생)
$CSSH$M1_PUB "
cat <<'EOF' | kubectl apply -f -
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: $CEPH_IMAGE
    allowUnsupported: false
  dataDirHostPath: /var/lib/rook
  skipUpgradeChecks: false
  mon:
    count: 1
    allowMultiplePerNode: false
  mgr:
    count: 1
    modules:
      - name: pg_autoscaler
        enabled: true
  dashboard:
    enabled: true
    ssl: false
  placement:
    all:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: node-role.kubernetes.io/control-plane
                  operator: DoesNotExist
  storage:
    useAllNodes: false
    useAllDevices: false
    nodes:
      - name: worker-1
        devices:
          - name: nvme1n1
          - name: nvme2n1
      - name: worker-2
        devices:
          - name: nvme1n1
          - name: nvme2n1
      - name: worker-3
        devices:
          - name: nvme1n1
          - name: nvme2n1
      - name: worker-4
        devices:
          - name: nvme1n1
          - name: nvme2n1
EOF
"

# [안정화 대기 2] CephCluster CR 적용 후 CSI DaemonSet 배포가 시작됨
# CSI pod들이 일제히 API server 연결을 맺기 전에 잠시 대기
echo "  CSI 배포 시작 대기 (30초)..."
sleep 30

echo "=============================="
echo " Step 1-4: Ceph 클러스터 HEALTH_OK 대기"
echo "=============================="
echo "  (mon 1개 + OSD 초기화 포함 최대 10분 소요)"
$CSSH$M1_PUB "
  for i in \$(seq 1 60); do
    STATUS=\$(kubectl -n rook-ceph get cephcluster rook-ceph \
      -o jsonpath='{.status.ceph.health}' 2>/dev/null || echo 'PENDING')
    echo \"  [\$i/60] Ceph 상태: \$STATUS\"
    [ \"\$STATUS\" = 'HEALTH_OK' ] && break
    sleep 10
  done
  kubectl -n rook-ceph get cephcluster rook-ceph
  kubectl -n rook-ceph get pods -o wide
"

echo "=============================="
echo " Step 1-5: CephBlockPool + StorageClass (RBD)"
echo "=============================="
# replication size=2: mon 1개 환경에서 size=3은 PG undersized 경고 유발
$CSSH$M1_PUB "
cat <<'EOF' | kubectl apply -f -
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: replicapool
  namespace: rook-ceph
spec:
  replicated:
    size: 2
    requireSafeReplicaSize: false
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-rbd
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: replicapool
  imageFormat: \"2\"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF
"

echo "=============================="
echo " Step 1-6: CephFilesystem + StorageClass (CephFS)"
echo "=============================="
$CSSH$M1_PUB "
cat <<'EOF' | kubectl apply -f -
apiVersion: ceph.rook.io/v1
kind: CephFilesystem
metadata:
  name: labfs
  namespace: rook-ceph
spec:
  metadataPool:
    replicated:
      size: 2
  dataPools:
    - name: replicated
      replicated:
        size: 2
  preserveFilesystemOnDelete: false
  metadataServer:
    activeCount: 1
    activeStandby: false
    placement:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: node-role.kubernetes.io/control-plane
                  operator: DoesNotExist
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-cephfs
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: rook-ceph
  fsName: labfs
  pool: labfs-replicated
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-cephfs-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF
"

echo "=============================="
echo " Step 1-7: StorageClass 확인"
echo "=============================="
kubectl get storageclass
kubectl -n rook-ceph get pods -o wide

echo ""
echo "✅ Step 1 완료 - StorageClass: ceph-rbd, ceph-cephfs"
echo "   다음: scripts/02_gpfs_install.sh (IBM 패키지 필요)"
