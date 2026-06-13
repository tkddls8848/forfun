#!/bin/bash
# Stage 2: Ceph ?¨Ïù¥???ÑÍ≤∞
#   [1/2] Ceph Î∞±Ïóî??(bootstrap ??OSD ??CephFS ??RBD pool)
#   [2/2] Ceph CSI ?§Ïπò (ceph-rbd, ceph-cephfs StorageClass)
# ?ÑÏ†ú: start_1_infra_k3s.sh ?ÑÎ£å ??lab.env Ï°¥Ïû¨
# Î°§Î∞±: rollback_2_ceph.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAB_ENV="$LAB_ROOT/lab.env"

if [ ! -f "$LAB_ENV" ]; then
  echo "??$LAB_ENV ?ÜÏùå ??start_1_infra_k3s.sh Î•?Î®ºÏ? ?§Ìñâ?òÏÑ∏??"
  exit 1
fi
set -a; source "$LAB_ENV"; set +a

SSH_KEY="${SSH_KEY_PATH:-${SSH_KEY:-$HOME/.ssh/storage-lab.pem}}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [1/2] Ceph Î∞±Ïóî??
echo "       bootstrap ??OSD ??CephFS ??RBD pool"
echo "=============================="
# bash -s < script Î∞©Ïãù?Ä cephadm shell(podman)??stdin???åÎπÑ??# ?§ÌÅ¨Î¶ΩÌä∏ ?ÑÎ∞òÎ∂ÄÍ∞Ä ?§Ìñâ?òÏ? ?äÎäî Î¨∏Ï†úÍ∞Ä ?àÏùå ??scp ???åÏùºÎ°??§Ìñâ
scp -O $SSH_OPTS "$LAB_ROOT/scripts/system/02_ceph_backend.sh" \
  ec2-user@$BACKEND_IP:/tmp/02_ceph_backend.sh
ssh $SSH_OPTS ec2-user@$BACKEND_IP \
  "sudo CEPH_OSD_1_VOL='$CEPH_OSD_1_VOL' CEPH_OSD_2_VOL='$CEPH_OSD_2_VOL' bash /tmp/02_ceph_backend.sh"

# FSID / admin key ?òÏßë ??lab.env ?Ä??CEPH_FSID=$(ssh $SSH_OPTS ec2-user@$BACKEND_IP \
  "sudo cephadm shell -- ceph fsid 2>/dev/null" | tr -d '\r\n')
CEPH_ADMIN_KEY=$(ssh $SSH_OPTS ec2-user@$BACKEND_IP \
  "sudo cephadm shell -- ceph auth get-key client.admin 2>/dev/null" | tr -d '\r\n')

if [ -z "$CEPH_FSID" ] || [ -z "$CEPH_ADMIN_KEY" ]; then
  echo "??CEPH_FSID ?êÎäî CEPH_ADMIN_KEY ?òÏßë ?§Ìå®."
  exit 1
fi

grep -v "^CEPH_FSID=\|^CEPH_ADMIN_KEY=" "$LAB_ENV" > "${LAB_ENV}.tmp" \
  && mv "${LAB_ENV}.tmp" "$LAB_ENV"
cat >> "$LAB_ENV" <<EOF
CEPH_FSID=${CEPH_FSID}
CEPH_ADMIN_KEY='${CEPH_ADMIN_KEY}'
EOF
echo "  CEPH_FSID / CEPH_ADMIN_KEY ??$LAB_ENV ?Ä???ÑÎ£å ??

echo "=============================="
echo " [2/2] Ceph CSI ?§Ïπò"
echo "       ceph-rbd, ceph-cephfs StorageClass ??frontend"
echo "=============================="
scp -O $SSH_OPTS "$LAB_ROOT/scripts/system/04_csi_ceph.sh" ec2-user@$FRONTEND_IP:~/

ssh $SSH_OPTS ec2-user@$FRONTEND_IP \
  "sudo BACKEND_PRIVATE_IP='$BACKEND_PRIVATE_IP' \
   CEPH_FSID='$CEPH_FSID' \
   CEPH_ADMIN_KEY='$CEPH_ADMIN_KEY' \
   SCRIPT_DIR=/home/ec2-user \
   bash /home/ec2-user/04_csi_ceph.sh"

echo ""
echo "??Stage 2 ?ÑÎ£å ??Ceph ?¥Îü¨?§ÌÑ∞ + CSI Íµ¨ÏÑ±??
echo "  StorageClass: ceph-rbd, ceph-cephfs"
echo "  ?§Ïùå ?®Í≥Ñ: bash scripts/lifecycle/start_3_beegfs.sh"
