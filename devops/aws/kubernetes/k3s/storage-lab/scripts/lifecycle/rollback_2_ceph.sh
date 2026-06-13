#!/bin/bash
# Rollback Stage 2: Ceph CSI ?œê±° ??Ceph ?´ëŸ¬?¤í„° ?œê±°
# ?¤í–‰ ?œì„œ: rollback_3_beegfs.sh ??rollback_2_ceph.sh ??rollback_1_infra.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAB_ENV="$LAB_ROOT/lab.env"

if [ ! -f "$LAB_ENV" ]; then
  echo "??$LAB_ENV ?†ìŒ ??ë¡¤ë°±???íƒœê°€ ?†ìŠµ?ˆë‹¤."
  exit 1
fi
set -a; source "$LAB_ENV"; set +a

if [ -z "$CEPH_FSID" ]; then
  echo "? ï¸  lab.env ??CEPH_FSID ?†ìŒ ??Ceph ê°€ ?¤ì¹˜?˜ì? ?Šì•˜ê±°ë‚˜ ?´ë? ?œê±°??"
  exit 0
fi

SSH_KEY="${SSH_KEY_PATH:-${SSH_KEY:-$HOME/.ssh/storage-lab.pem}}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [1/2] Ceph CSI ?œê±° (Frontend)"
echo "=============================="
ssh $SSH_OPTS ec2-user@$FRONTEND_IP 'sudo bash -s' <<'EOF'
export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"

if command -v helm &>/dev/null; then
  helm uninstall ceph-csi-rbd    -n ceph-csi-rbd    2>/dev/null || true
  helm uninstall ceph-csi-cephfs -n ceph-csi-cephfs 2>/dev/null || true
fi
kubectl delete namespace ceph-csi-rbd ceph-csi-cephfs --ignore-not-found
kubectl delete storageclass ceph-rbd ceph-cephfs --ignore-not-found
echo "Ceph CSI ?œê±° ?„ë£Œ"
EOF

echo "=============================="
echo " [2/2] Ceph ?´ëŸ¬?¤í„° ?œê±° (Backend)"
echo "       fsid: $CEPH_FSID"
echo "=============================="
ssh $SSH_OPTS ec2-user@$BACKEND_IP \
  "sudo cephadm rm-cluster --force --zap-osds --fsid '$CEPH_FSID'"

grep -v "^CEPH_FSID=\|^CEPH_ADMIN_KEY=" "$LAB_ENV" > "${LAB_ENV}.tmp" \
  && mv "${LAB_ENV}.tmp" "$LAB_ENV"
echo "  CEPH_FSID / CEPH_ADMIN_KEY ??lab.env ?ì„œ ?œê±° ?„ë£Œ"

echo ""
echo "??Stage 2 ë¡¤ë°± ?„ë£Œ"
echo "  ?¤ìŒ ?¨ê³„ (?„ìš” ??: bash scripts/lifecycle/rollback_1_infra.sh"
