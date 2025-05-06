#!/bin/bash
# Ceph CSI deployment script using Helm

# Install Helm
echo "[1/5] Installing Helm..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Add Ceph CSI Helm repository
echo "[2/5] Adding Ceph CSI Helm repository..."
helm repo add ceph-csi https://ceph.github.io/csi-charts
helm repo update
helm search repo ceph-csi

# Create namespace for Ceph CSI
echo "[3/5] Creating namespace for Ceph CSI..."
kubectl create namespace ceph-csi-rbd

# Get Ceph cluster ID and monitor IPs
echo "[4/5] Getting Ceph configuration values..."
FSID=$(ceph fsid)
MON_IPS=$(ceph mon dump | grep mon | awk '{print $2}' | sed 's/\/.*//' | paste -sd ',' -)
ADMIN_KEY=$(ceph auth get-key client.admin)

# Install Ceph CSI RBD driver
echo "[5/5] Installing Ceph CSI RBD driver..."
helm install \
  --namespace ceph-csi-rbd \
  --set configMapName=ceph-csi-config \
  --set csiConfig="[{\"clusterID\":\"${FSID}\",\"monitors\":[\"${MON_IPS}\"]}]" \
  --set ceph-csi-rbd.provisioner.nodeSelector.kubernetes\\.io/hostname=k8s-master \
  --set ceph-csi-rbd.nodeplugin.nodeSelector.kubernetes\\.io/hostname=k8s-worker-1 \
  ceph-csi-rbd ceph-csi/ceph-csi-rbd

# Create RBD StorageClass
echo "Creating RBD StorageClass..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ceph-admin-secret
  namespace: ceph-csi-rbd
type: kubernetes.io/rbd
data:
  userID: $(echo -n admin | base64)
  userKey: $(echo -n ${ADMIN_KEY} | base64)
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-rbd
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: ${FSID}
  pool: rbd
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: ceph-admin-secret
  csi.storage.k8s.io/provisioner-secret-namespace: ceph-csi-rbd
  csi.storage.k8s.io/controller-expand-secret-name: ceph-admin-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: ceph-csi-rbd
  csi.storage.k8s.io/node-stage-secret-name: ceph-admin-secret
  csi.storage.k8s.io/node-stage-secret-namespace: ceph-csi-rbd
reclaimPolicy: Delete
allowVolumeExpansion: true
mountOptions:
  - discard
EOF

# Create test PVC and Pod
echo "Creating test PVC and Pod..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: ceph-rbd
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
  - name: test-pod
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: test-vol
      mountPath: /mnt
  volumes:
  - name: test-vol
    persistentVolumeClaim:
      claimName: test-pvc
EOF

echo "Ceph CSI deployment completed. Check status with:"
echo "kubectl -n ceph-csi-rbd get pods"
echo "kubectl get pvc test-pvc"
echo "kubectl get sc"


