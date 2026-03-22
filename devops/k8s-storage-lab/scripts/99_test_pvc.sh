#!/bin/bash
set -e
export KUBECONFIG=~/.kube/config-k8s-storage-lab

echo "=============================="
echo " Test 1: ceph-rbd (Block RWO)"
echo "=============================="
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc-rbd
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ceph-rbd
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-rbd
spec:
  containers:
  - name: test
    image: busybox
    command: ["/bin/sh", "-c", "echo 'ceph-rbd OK' > /data/test.txt && cat /data/test.txt && sleep 60"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-pvc-rbd
  restartPolicy: Never
EOF

echo "=============================="
echo " Test 2: ceph-cephfs (File RWX)"
echo "=============================="
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc-cephfs
spec:
  accessModes: [ReadWriteMany]
  storageClassName: ceph-cephfs
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-cephfs
spec:
  containers:
  - name: test
    image: busybox
    command: ["/bin/sh", "-c", "echo 'cephfs OK' > /data/test.txt && cat /data/test.txt && sleep 60"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-pvc-cephfs
  restartPolicy: Never
EOF

echo "=============================="
echo " Test 3: gpfs-scale (GPFS RWX)"
echo "=============================="
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc-gpfs
spec:
  accessModes: [ReadWriteMany]
  storageClassName: gpfs-scale
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-gpfs
spec:
  containers:
  - name: test
    image: busybox
    command: ["/bin/sh", "-c", "echo 'gpfs OK' > /data/test.txt && cat /data/test.txt && sleep 60"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-pvc-gpfs
  restartPolicy: Never
EOF

echo ""
echo "--- PVC 바인딩 대기 (최대 120초) ---"
for pvc in test-pvc-rbd test-pvc-cephfs test-pvc-gpfs; do
  echo -n "  $pvc: "
  kubectl wait pvc/$pvc --for=jsonpath='{.status.phase}'=Bound --timeout=120s \
    && echo "✅ Bound" || echo "❌ 실패"
done

echo ""
echo "--- Pod 상태 ---"
kubectl wait pod/test-pod-rbd    --for=condition=ready --timeout=120s || true
kubectl wait pod/test-pod-cephfs --for=condition=ready --timeout=120s || true
kubectl wait pod/test-pod-gpfs   --for=condition=ready --timeout=120s || true
kubectl get pods,pvc

echo ""
echo "--- 로그 확인 ---"
kubectl logs test-pod-rbd    || true
kubectl logs test-pod-cephfs || true
kubectl logs test-pod-gpfs   || true

echo ""
echo "=============================="
echo " 정리 명령어"
echo "=============================="
echo "  kubectl delete pod test-pod-rbd test-pod-cephfs test-pod-gpfs"
echo "  kubectl delete pvc test-pvc-rbd test-pvc-cephfs test-pvc-gpfs"
