#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"


echo "=============================="
echo " [4/5] Ceph 클러스터 구성 (rook-ceph)"
echo "=============================="
bash scripts/02_ceph_install.sh

echo "=============================="
echo " [5/5] 안내"
echo "=============================="
echo ""
echo "⚠️  GPFS는 IBM 패키지 수동 다운로드 후 진행 필요:"
echo "   1. ./gpfs-packages/ 에 .deb 파일 배치"
echo "   2. bash scripts/04_gpfs_install.sh"
echo "   3. bash scripts/05_nsd_setup.sh"
echo "   4. bash scripts/06_csi_gpfs.sh"
echo "   5. bash scripts/99_test_pvc.sh"
echo ""
echo "✅ 인프라, K8s, Ceph(rook) 구성 완료!"
echo "   StorageClass: ceph-rbd, ceph-cephfs"
echo "   kubeconfig  : ~/.kube/config-k8s-storage-lab"
