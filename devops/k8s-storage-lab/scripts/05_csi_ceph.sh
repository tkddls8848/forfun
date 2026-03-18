#!/bin/bash
set -e
source scripts/.env

export KUBECONFIG=~/.kube/config-k8s-storage-lab
SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

echo "=============================="
echo " Step 5: Helm 설치"
echo "=============================="
$CSSH$M1_PUB "
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
"

echo "=============================="
echo " Step 5-1: ceph-csi Helm repo"
echo "=============================="
$CSSH$M1_PUB "
  helm repo add ceph-csi https://ceph.github.io/csi-charts
  helm repo update
  kubectl create namespace ceph-csi-rbd    || true
  kubectl create namespace ceph-csi-cephfs || true
"

CEPH_FSID=$($CSSH$C1_PUB "sudo ceph fsid")
CEPH_MON_IP=$C1_PRIV
CEPH_KEY=$($CSSH$C1_PUB "sudo ceph auth get-key client.k8s 2>/dev/null || sudo ceph auth get-or-create client.k8s mon 'profile rbd' osd 'profile rbd pool=rbd' | grep key | awk '{print \$3}'")

echo "=============================="
echo " Step 5-2: ceph-csi-rbd (Block)"
echo "=============================="
$CSSH$M1_PUB "
cat <<EOF > /tmp/csi-rbd-values.yaml
csiConfig:
  - clusterID: \"$CEPH_FSID\"
    monitors:
      - \"$CEPH_MON_IP:6789\"

secret:
  create: true
  name: csi-rbd-secret
  userID: k8s
  userKey: \"$CEPH_KEY\"

storageClass:
  create: true
  name: ceph-rbd
  clusterID: \"$CEPH_FSID\"
  pool: rbd
  reclaimPolicy: Delete
  allowVolumeExpansion: true
EOF

helm upgrade --install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
  -n ceph-csi-rbd \
  -f /tmp/csi-rbd-values.yaml

kubectl wait --for=condition=ready pod \
  -l app=ceph-csi-rbd \
  -n ceph-csi-rbd \
  --timeout=120s
"

echo "=============================="
echo " Step 5-3: ceph-csi-cephfs (File/RWX)"
echo "=============================="
CEPHFS_KEY=$($CSSH$C1_PUB "sudo ceph auth get-or-create client.k8s-fs mds 'allow rw' mon 'allow r' osd 'allow rw pool=cephfs_data' | grep key | awk '{print \$3}'")

$CSSH$M1_PUB "
cat <<EOF > /tmp/csi-cephfs-values.yaml
csiConfig:
  - clusterID: \"$CEPH_FSID\"
    monitors:
      - \"$CEPH_MON_IP:6789\"

secret:
  create: true
  name: csi-cephfs-secret
  adminID: k8s-fs
  adminKey: \"$CEPHFS_KEY\"

storageClass:
  create: true
  name: ceph-cephfs
  clusterID: \"$CEPH_FSID\"
  fsName: labfs
  reclaimPolicy: Delete
  allowVolumeExpansion: true
EOF

helm upgrade --install ceph-csi-cephfs ceph-csi/ceph-csi-cephfs \
  -n ceph-csi-cephfs \
  -f /tmp/csi-cephfs-values.yaml

kubectl wait --for=condition=ready pod \
  -l app=ceph-csi-cephfs \
  -n ceph-csi-cephfs \
  --timeout=120s
"

kubectl get storageclass

echo ""
echo "✅ Step 5 완료 - StorageClass: ceph-rbd, ceph-cephfs"
echo "   다음: scripts/06_csi_gpfs.sh"
