#!/usr/bin/env bash
set -euo pipefail

## ceph filesystem
## get filesystem info by toolbox container command 'ceph fs ls'
## name: myfs, metadata pool: myfs-metadata, data pools: [myfs-replicated]
ROOK_HOME="${ROOK_HOME:-$HOME/rook}"
WORKDIR="${WORKDIR:-$HOME/k8s-install-manifests}"
cd "$ROOK_HOME/deploy/examples"
kubectl apply -f filesystem.yaml
kubectl -n rook-ceph wait --for=condition=Ready cephfilesystem/myfs --timeout=10m

## test ceph filesystem shared directory /mnt/cephfs
install -m 0755 -d "$WORKDIR"
cat > "$WORKDIR/cephfs-storageclass.yaml" << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-cephfs
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: rook-ceph # 파일시스템 네임스페이스
  fsName: myfs # 파일시스템 이름
  pool: myfs-replicated # 파일시스템 데이터풀 이름 (toolbox에서 ceph fs ls를 통해 확인)
  # Ceph 내의 사용자 인증 정보
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-cephfs-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
reclaimPolicy: Retain
EOF
kubectl apply -f "$WORKDIR/cephfs-storageclass.yaml"

if [[ "${RUN_DEMO_PODS:-false}" != "true" ]]; then
  exit 0
fi

cat > "$WORKDIR/cephfs-pvc.yaml" << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cephfs-pvc
spec:
  storageClassName: rook-cephfs
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
EOF
cat > "$WORKDIR/cephfs-pods.yaml" << EOF
apiVersion: v1
kind: Pod
metadata:
  name: cephfs-test-pod-1
spec:
  containers:
    - name: cephfs-container
      image: busybox
      command: ["sh", "-c", "echo 'Hello from Pod 1' > /mnt/cephfs/pod1.txt; sleep 3600"] ## 공유 파일 생성
      volumeMounts:
        - mountPath: "/mnt/cephfs" ## 여러 container간 공유 디렉토리
          name: cephfs-storage
  volumes:
    - name: cephfs-storage
      persistentVolumeClaim:
        claimName: cephfs-pvc
---
apiVersion: v1
kind: Pod
metadata:
  name: cephfs-test-pod-2
spec:
  containers:
    - name: cephfs-container
      image: busybox
      command: ["sh", "-c", "echo 'Hello from Pod 2' > /mnt/cephfs/pod2.txt; sleep 3600"] ## 공유 파일 생성
      volumeMounts:
        - mountPath: "/mnt/cephfs" ## 여러 container간 공유 디렉토리
          name: cephfs-storage
  volumes:
    - name: cephfs-storage
      persistentVolumeClaim:
        claimName: cephfs-pvc
EOF

kubectl apply -f "$WORKDIR/cephfs-pvc.yaml" -f "$WORKDIR/cephfs-pods.yaml"
