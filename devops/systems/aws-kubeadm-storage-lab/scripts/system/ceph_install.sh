#!/bin/bash
set -e

# Lock ?Œì¼ ?•ì¸ - ?™ì‹œ ?¤í–‰ ë°©ì?
LOCK_FILE="/tmp/ceph-setup.lock"
if [ -f "$LOCK_FILE" ]; then
  echo "???¤ë¥¸ ?„ë¡œ?¸ìŠ¤ê°€ Ceph ?¤ì • ì¤‘ì…?ˆë‹¤ (lock: $LOCK_FILE)"
  exit 1
fi

source scripts/.env

export KUBECONFIG=~/.kube/config-k8s-storage-lab
SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

# K8s ?´ëŸ¬?¤í„° ì¡´ì¬ ?•ì¸
if ! kubectl cluster-info &>/dev/null; then
  echo "??K8s ?´ëŸ¬?¤í„°???‘ê·¼?????†ìŠµ?ˆë‹¤."
  echo "   ë¨¼ì? start_k8s.sh ë¥??¤í–‰?˜ì„¸??"
  exit 1
fi

ROOK_VERSION="v1.16.6"
CEPH_IMAGE="quay.io/ceph/ceph:v19.2.3"

# Lock ?Œì¼ ?ì„± ë°?trap ?¤ì •
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

WORKER_COUNT=${#WORKER_PUBS[@]}

# ì¹´ìš´?¸ë‹¤???œì‹œ ?¨ìˆ˜
countdown() {
  local sec=$1
  local msg=$2
  for s in $(seq $sec -1 1); do
    printf "\r  [?€ê¸? %s - %2ds ?¨ìŒ..." "$msg" $s
    sleep 1
  done
  printf "\r  [?„ë£Œ] %s                    \n" "$msg"
}

echo "=============================="
echo " Step 1: Helm ?¤ì¹˜ (master-1)"
echo "=============================="
$CSSH$M1_PUB "
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  helm version
"

echo "=============================="
echo " Step 1-1: rook-ceph Helm repo ì¶”ê?"
echo "=============================="
$CSSH$M1_PUB "
  helm repo add rook-release https://charts.rook.io/release
  helm repo update
  kubectl create namespace rook-ceph || true
"

echo "=============================="
echo " Step 1-2: rook-ceph Operator ë°°í¬"
echo "=============================="
$CSSH$M1_PUB "helm upgrade --install rook-ceph rook-release/rook-ceph --namespace rook-ceph --version $ROOK_VERSION"
echo "  [?€ê¸? rook-ceph-operator Deployment rollout ?„ë£Œ ?€ê¸?(ìµœë? 300s)..."
$CSSH$M1_PUB "kubectl -n rook-ceph rollout status deployment/rook-ceph-operator --timeout=300s"

# operator??CRD watch ?°ê²°(20+ê°????ˆì •?”ë  ?œê°„ ?•ë³´
# ë°”ë¡œ CephClusterë¥?ë°°í¬?˜ë©´ watch ??’ + reconcile ë£¨í”„ë¡?etcd ê³¼ë???ë°œìƒ
countdown 60 "rook-ceph-operator CRD watch ?ˆì •??
$CSSH$M1_PUB "kubectl -n rook-ceph get pods"

echo "=============================="
echo " Step 1-2-1: ?Œì»¤ ?¸ë“œ rbd ëª¨ë“ˆ ë¡œë“œ ?•ì¸"
echo "=============================="
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  NODE_IP="${WORKER_PUBS[$i]}"
  NODE_NAME="worker-$((i + 1))"
  $CSSH$NODE_IP "
    if lsmod | grep -q '^rbd'; then
      echo '  ??rbd ëª¨ë“ˆ ë¡œë“œ?? $NODE_NAME'
    else
      echo '  rbd ëª¨ë“ˆ ë¡œë“œ ?œë„: $NODE_NAME'
      sudo modprobe rbd
      lsmod | grep -q '^rbd' && echo '  ??rbd ë¡œë“œ ?±ê³µ' || echo '  ??rbd ë¡œë“œ ?¤íŒ¨ - linux-modules-extra-aws ?•ì¸ ?„ìš”'
    fi
  "
done

echo "=============================="
echo " Step 1-3: CephCluster CR ë°°í¬"
echo "=============================="

# OSD ?˜ê? ???´ìƒ ?˜ì? ?Šê³  ?°ì† 5???™ì¼?????ˆì •?¼ë¡œ ?ë‹¨ (ìµœë? 8ë¶?
# useAllDevices: true ?´ë?ë¡?ëª©í‘œ ?˜ë? ?˜ë“œì½”ë”©?˜ì? ?ŠìŒ
wait_osd_running() {
  $CSSH$M1_PUB "
    PREV=0
    STABLE=0
    for i in \$(seq 1 48); do
      UP=\$(kubectl -n rook-ceph get pods -l app=rook-ceph-osd --no-headers 2>/dev/null | grep -c Running || true)
      echo \"  [?€ê¸? OSD ê¸°ë™ ?•ì¸ [\$i/48] Running: \$UP\"
      if [ \"\$UP\" -gt 0 ] && [ \"\$UP\" -eq \"\$PREV\" ]; then
        STABLE=\$((STABLE + 1))
        [ \"\$STABLE\" -ge 5 ] && echo \"  ??OSD ?ˆì • ?•ì¸ (5???°ì† \$UP ê°?\" && break
      else
        STABLE=0
      fi
      PREV=\$UP
      sleep 10
    done
  "
  countdown 45 "OSD I/O ì´ˆê¸°??ë°?API server ?ˆì •??
}

# CephCluster CR ë°°í¬ (useAllNodes: true ??K8s ?¸ë“œëª…ì— ë¬´ê??˜ê²Œ control-plane ?œì™¸ ?„ì²´ ?ìš©)
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
  cephConfig:
    global:
      osd_pool_default_size: \"2\"
      osd_pool_default_min_size: \"1\"
  storage:
    useAllNodes: true
    useAllDevices: false
    deviceFilter: "^nvme1n1$"
CREOF
"

echo "  deviceFilter: ^nvme1n1$ ??Ceph OSD ?„ìš© ?”ìŠ¤?¬ë§Œ ?¬ìš© (/dev/xvdb, nvme2n1=BeeGFS ?œì™¸)"
wait_osd_running

echo "=============================="
echo " Step 1-4: Ceph ?´ëŸ¬?¤í„° HEALTH_OK ?€ê¸?
echo "=============================="
$CSSH$M1_PUB "
  for i in \$(seq 1 90); do
    STATUS=\$(kubectl -n rook-ceph get cephcluster rook-ceph \
      -o jsonpath='{.status.ceph.health}' 2>/dev/null || echo 'PENDING')
    echo \"  [?€ê¸? Ceph ?´ëŸ¬?¤í„° ?íƒœ ?•ì¸ [\$i/90]: \$STATUS\"
    [ \"\$STATUS\" = 'HEALTH_OK' ] && echo '  ??HEALTH_OK ?¬ì„±' && break
    sleep 10
  done
  kubectl -n rook-ceph get cephcluster rook-ceph
  kubectl -n rook-ceph get pods -o wide
"

echo "=============================="
echo " Step 1-4-1: CSI Provisioner master ?¸ë“œ ë°°ì¹˜"
echo "=============================="
$CSSH$M1_PUB "
cat > /tmp/csi-patch.yaml << 'PATCHEOF'
data:
  CSI_PROVISIONER_NODE_AFFINITY: node-role.kubernetes.io/control-plane=
  CSI_PROVISIONER_TOLERATIONS: '[{\"key\":\"node-role.kubernetes.io/control-plane\",\"operator\":\"Exists\",\"effect\":\"NoSchedule\"}]'
PATCHEOF
  kubectl -n rook-ceph patch configmap rook-ceph-operator-config \
    --type merge --patch-file /tmp/csi-patch.yaml
  kubectl rollout restart deployment/csi-cephfsplugin-provisioner \
    deployment/csi-rbdplugin-provisioner -n rook-ceph
  kubectl -n rook-ceph rollout status deployment/csi-cephfsplugin-provisioner --timeout=180s
  kubectl -n rook-ceph rollout status deployment/csi-rbdplugin-provisioner --timeout=180s
  echo '  ??CSI Provisioner ??master ?¸ë“œ ?¬ë°°ì¹??„ë£Œ'
"

echo "=============================="
echo " Step 1-4-2: rook-ceph-tools ë°°í¬"
echo "=============================="
$CSSH$M1_PUB "kubectl apply -f https://raw.githubusercontent.com/rook/rook/$ROOK_VERSION/deploy/examples/toolbox.yaml"
echo "  [?€ê¸? rook-ceph-tools ê¸°ë™ ?€ê¸?.."
$CSSH$M1_PUB "kubectl -n rook-ceph rollout status deploy/rook-ceph-tools --timeout=120s"


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
echo " Step 1-7: StorageClass ?•ì¸"
echo "=============================="
kubectl get storageclass
kubectl -n rook-ceph get pods -o wide

echo "=============================="
echo " Step 1-8: rook-ceph ?íƒœ ?•ì¸"
echo "=============================="
echo "--- CephCluster ?íƒœ ---"
kubectl -n rook-ceph get cephcluster rook-ceph \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,HEALTH:.status.ceph.health

echo ""
echo "--- CSI ?œë¼?´ë²„ ---"
kubectl get csidrivers

echo "=============================="
echo " Step 1-9: Ceph Dashboard ?‘ì† ?•ë³´"
echo "=============================="
$CSSH$M1_PUB "
  NODE_PORT=\$(kubectl -n rook-ceph get svc rook-ceph-mgr-dashboard \
    -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo 'NodePort ?†ìŒ')
  ADMIN_PASS=\$(kubectl -n rook-ceph get secret rook-ceph-dashboard-password \
    -o jsonpath='{.data.password}' | base64 --decode)
  echo \"Dashboard NodePort : \$NODE_PORT\"
  echo \"?‘ì† URL           : http://<worker-IP>:\$NODE_PORT\"
  echo \"Dashboard ë¹„ë?ë²ˆí˜¸ : \$ADMIN_PASS\"
"

echo ""
echo "??Ceph ?¤ì¹˜ ?„ë£Œ - StorageClass: ceph-rbd, ceph-cephfs"
echo "   ?¤ìŒ (BeeGFS): bash scripts/lifecycle/start_beegfs.sh"
