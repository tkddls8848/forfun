#!/bin/bash
# rook-ceph 방식에서 CSI는 operator가 자동 설치함
# 이 스크립트는 rook-ceph 상태 확인용
set -e
source scripts/.env

export KUBECONFIG=~/.kube/config-k8s-storage-lab
SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

echo "=============================="
echo " Step 5: rook-ceph 상태 확인"
echo "=============================="

echo "--- CephCluster 상태 ---"
kubectl -n rook-ceph get cephcluster rook-ceph \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,HEALTH:.status.ceph.health

echo ""
echo "--- rook-ceph Pods ---"
kubectl -n rook-ceph get pods -o wide

echo ""
echo "--- StorageClass ---"
kubectl get storageclass

echo ""
echo "--- CSI 드라이버 ---"
kubectl get csidrivers

echo "=============================="
echo " Step 5-1: Ceph Dashboard URL"
echo "=============================="
$CSSH$M1_PUB "
  NODE_PORT=\$(kubectl -n rook-ceph get svc rook-ceph-mgr-dashboard \
    -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo 'NodePort 없음')
  echo \"Dashboard NodePort: \$NODE_PORT\"
  echo \"접속 URL: http://<worker-IP>:\$NODE_PORT\"
  ADMIN_PASS=\$(kubectl -n rook-ceph get secret rook-ceph-dashboard-password \
    -o jsonpath='{.data.password}' | base64 --decode)
  echo \"Dashboard 비밀번호: \$ADMIN_PASS\"
"

echo ""
echo "✅ Step 5 완료"
echo "   다음: scripts/06_csi_gpfs.sh (IBM 패키지 필요)"
