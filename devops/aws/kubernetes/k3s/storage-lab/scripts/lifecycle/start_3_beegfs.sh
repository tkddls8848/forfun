#!/bin/bash
# Stage 3: BeeGFS ?¬ì´???„ê²°
#   [1/2] BeeGFS ë°±ì—”??(?”ìŠ¤??ì¤€ë¹???LVM ?¤íŠ¸?¼ì´????XFS ???œë¹„??ê¸°ë™)
#   [2/2] BeeGFS CSI ?¤ì¹˜ (ì»¤ë„ ëª¨ë“ˆ ë¹Œë“œ ??beegfs-scratch StorageClass)
# ?„ì œ: start_2_ceph.sh ?„ë£Œ ??lab.env ??CEPH_FSID / CEPH_ADMIN_KEY ì¡´ì¬
# ë¡¤ë°±: rollback_3_beegfs.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAB_ENV="$LAB_ROOT/lab.env"

if [ ! -f "$LAB_ENV" ]; then
  echo "??$LAB_ENV ?†ìŒ ??start_1_infra_k3s.sh, start_2_ceph.sh ë¥?ë¨¼ì? ?¤í–‰?˜ì„¸??"
  exit 1
fi
set -a; source "$LAB_ENV"; set +a

: "${CEPH_FSID:?lab.env ??CEPH_FSID ?†ìŒ ??start_2_ceph.sh ë¥?ë¨¼ì? ?¤í–‰?˜ì„¸??"

SSH_KEY="${SSH_KEY_PATH:-${SSH_KEY:-$HOME/.ssh/storage-lab.pem}}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [1/2] BeeGFS ë°±ì—”??
echo "       ?”ìŠ¤??ì¤€ë¹???LVM ?¤íŠ¸?¼ì´????XFS ???œë¹„??ê¸°ë™"
echo "=============================="
ssh $SSH_OPTS ec2-user@$BACKEND_IP \
  "sudo BEEGFS_STORAGE_1_VOL='$BEEGFS_STORAGE_1_VOL' BEEGFS_STORAGE_2_VOL='$BEEGFS_STORAGE_2_VOL' bash -s" \
  < "$LAB_ROOT/scripts/system/03_beegfs_backend.sh"

echo "=============================="
echo " [2/2] BeeGFS CSI ?¤ì¹˜"
echo "       ì»¤ë„ ëª¨ë“ˆ ë¹Œë“œ ??beegfs-scratch StorageClass ??frontend"
echo "=============================="
scp -O $SSH_OPTS "$LAB_ROOT/scripts/system/04_csi_beegfs.sh" ec2-user@$FRONTEND_IP:~/
scp -O $SSH_OPTS "$LAB_ROOT/scripts/system/05_verify.sh"     ec2-user@$FRONTEND_IP:~/

ssh $SSH_OPTS ec2-user@$FRONTEND_IP \
  "sudo BACKEND_PRIVATE_IP='$BACKEND_PRIVATE_IP' \
   SCRIPT_DIR=/home/ec2-user \
   bash /home/ec2-user/04_csi_beegfs.sh"

echo ""
echo "??Stage 3 ?„ë£Œ ??BeeGFS + CSI êµ¬ì„±??
echo "  StorageClass: beegfs-scratch"
echo ""
echo "  ?„ì²´ StorageClass ?•ì¸:"
ssh $SSH_OPTS ec2-user@$FRONTEND_IP \
  "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get storageclass"
echo ""
echo "  Frontend : ssh -i $SSH_KEY ec2-user@$FRONTEND_IP"
echo "  Backend  : ssh -i $SSH_KEY ec2-user@$BACKEND_IP"
echo ""
echo "  ê²€ì¦?    : ssh -i $SSH_KEY ec2-user@$FRONTEND_IP 'bash ~/05_verify.sh'"
