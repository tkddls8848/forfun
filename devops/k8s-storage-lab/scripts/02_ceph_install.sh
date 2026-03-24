#!/bin/bash
set -e
source scripts/.env

export KUBECONFIG=~/.kube/config-k8s-storage-lab
SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

ROOK_VERSION="v1.13.0"
CEPH_IMAGE="quay.io/ceph/ceph:v18"

WORKER_COUNT=${#WORKER_PUBS[@]}

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

# [안정화 대기] operator의 CRD watch 연결(20+개)이 안정화될 시간 확보
# 바로 CephCluster를 배포하면 watch 폭풍 + reconcile 루프로 etcd 과부하 발생
echo "  CRD watch 안정화 대기 (60초)..."
sleep 60
$CSSH$M1_PUB "kubectl -n rook-ceph get pods"

echo "=============================="
echo " Step 1-2-1: 워커 노드 rbd 모듈 로드 확인"
echo "=============================="
# rbd 모듈이 로드되지 않으면 Ceph CSI의 RBD 볼륨 마운트 실패
# linux-modules-extra-aws와 커널 버전 불일치로 user_data에서 로드 실패했을 경우 대비
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  NODE_IP="${WORKER_PUBS[$i]}"
  NODE_NAME="worker-$((i + 1))"
  $CSSH$NODE_IP "
    if lsmod | grep -q '^rbd'; then
      echo '  ✅ rbd 모듈 로드됨: $NODE_NAME'
    else
      echo '  rbd 모듈 로드 시도: $NODE_NAME'
      sudo modprobe rbd
      lsmod | grep -q '^rbd' && echo '  ✅ rbd 로드 성공' || echo '  ❌ rbd 로드 실패 - linux-modules-extra-aws 확인 필요'
    fi
  "
done

echo "=============================="
echo " Step 1-3: CephCluster CR 배포 (워커별 순차 OSD 초기화)"
echo "=============================="
# NVMe OSD 일제 초기화 시 I/O 스파이크 → API server 과부하 방지를 위해 노드별 순차 추가
# useAllDevices: true: 미포맷 블록 디바이스 자동 감지 (디바이스명 하드코딩 제거)
# mon count=3: quorum 구성 (mon 과반수 이상 생존 시 클러스터 정상 운영)

# OSD Running 수가 최솟값에 도달한 뒤 연속 3회 안정 확인 후 반환 (최대 8분)
wait_osd_running() {
  local min_count=$1
  $CSSH$M1_PUB "
    STABLE=0
    for i in \$(seq 1 48); do
      UP=\$(kubectl -n rook-ceph get pods -l app=rook-ceph-osd --no-headers 2>/dev/null | grep -c Running || true)
      echo \"  [\$i/48] OSD Running: \$UP (목표: >= $min_count)\"
      if [ \"\$UP\" -ge $min_count ]; then
        STABLE=\$((STABLE + 1))
        [ \"\$STABLE\" -ge 3 ] && echo '  OSD 안정 확인 (3회 연속)' && break
      else
        STABLE=0
      fi
      sleep 10
    done
  "
  sleep 45  # OSD I/O 초기화 + API server 안정화 버퍼
}

# 워커를 1대씩 순차 추가하는 CephCluster CR 생성 함수
apply_ceph_cluster() {
  local node_list="$1"
  $CSSH$M1_PUB "
cat <<'CREOF' | kubectl apply -f -
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
    count: 3
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
    useAllDevices: true
    nodes:
$node_list
CREOF
"
}

# 워커를 1대씩 순차 추가
NODE_LIST=""
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  PHASE=$((i + 1))
  NODE_NAME="worker-$((i + 1))"
  NODE_LIST+="      - name: $NODE_NAME\n"
  echo "  [Phase $PHASE/$WORKER_COUNT] $NODE_NAME OSD 초기화..."
  apply_ceph_cluster "$(printf "$NODE_LIST")"
  wait_osd_running $PHASE
done

echo "=============================="
echo " Step 1-4: Ceph 클러스터 HEALTH_OK 대기"
echo "=============================="
echo "  (mon 3개 + OSD 초기화 포함 최대 15분 소요)"
$CSSH$M1_PUB "
  for i in \$(seq 1 90); do
    STATUS=\$(kubectl -n rook-ceph get cephcluster rook-ceph \
      -o jsonpath='{.status.ceph.health}' 2>/dev/null || echo 'PENDING')
    echo \"  [\$i/90] Ceph 상태: \$STATUS\"
    [ \"\$STATUS\" = 'HEALTH_OK' ] && break
    sleep 10
  done
  kubectl -n rook-ceph get cephcluster rook-ceph
  kubectl -n rook-ceph get pods -o wide
"

echo "=============================="
echo " Step 1-5: CephBlockPool + StorageClass (RBD)"
echo "=============================="
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
echo "   다음: scripts/04_gpfs_install.sh (IBM 패키지 필요)"
