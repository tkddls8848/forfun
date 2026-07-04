#!/bin/bash
# Stage 1: AWS ?¸í”„???ì„± + k3s ?¤ì¹˜
# ?„ë£Œ ??lab.env ???íƒœ ?€????Stage 2/3?????Œì¼??source ??# ë¡¤ë°±: rollback_1_infra.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAB_ENV="$LAB_ROOT/lab.env"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [0/3] ?¬ì „ ?”êµ¬?¬í•­ ?•ì¸"
echo "=============================="
MISSING=()
for cmd in tofu aws ssh scp; do
  command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
[ -f "$SSH_KEY" ] || MISSING+=("ssh-key:$SSH_KEY")
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "???„ë½????ª©: ${MISSING[*]}"
  exit 1
fi
echo "??ëª¨ë“  ?„ìˆ˜ ??ª© ?•ì¸ ?„ë£Œ"

echo "=============================="
echo " [1/3] AWS ?¸í”„???ì„±"
echo "=============================="
cd "$LAB_ROOT/opentofu"
tofu init
tofu apply -auto-approve

FRONTEND_IP=$(tofu output -raw frontend_public_ip)
BACKEND_IP=$(tofu output -raw backend_public_ip)
BACKEND_PRIVATE_IP=$(tofu output -raw backend_private_ip)
CEPH_OSD_1_VOL=$(tofu output -raw ceph_osd_1_volume_id)
CEPH_OSD_2_VOL=$(tofu output -raw ceph_osd_2_volume_id)
BEEGFS_STORAGE_1_VOL=$(tofu output -raw beegfs_storage_1_volume_id)
BEEGFS_STORAGE_2_VOL=$(tofu output -raw beegfs_storage_2_volume_id)

cat > "$LAB_ENV" <<EOF
SSH_KEY=${SSH_KEY}
FRONTEND_IP=${FRONTEND_IP}
BACKEND_IP=${BACKEND_IP}
BACKEND_PRIVATE_IP=${BACKEND_PRIVATE_IP}
CEPH_OSD_1_VOL=${CEPH_OSD_1_VOL}
CEPH_OSD_2_VOL=${CEPH_OSD_2_VOL}
BEEGFS_STORAGE_1_VOL=${BEEGFS_STORAGE_1_VOL}
BEEGFS_STORAGE_2_VOL=${BEEGFS_STORAGE_2_VOL}
EOF
echo "  ?íƒœ ?€???„ë£Œ: $LAB_ENV"
echo "  Frontend Public IP  : $FRONTEND_IP"
echo "  Backend Public IP   : $BACKEND_IP"
echo "  Ceph OSD volumes    : $CEPH_OSD_1_VOL, $CEPH_OSD_2_VOL"
echo "  BeeGFS volumes      : $BEEGFS_STORAGE_1_VOL, $BEEGFS_STORAGE_2_VOL"

echo "=============================="
echo " [2/3] SSH ?°ê²° ?€ê¸?
echo "=============================="
for IP in $FRONTEND_IP $BACKEND_IP; do
  echo -n "  $IP ?€ê¸?ì¤?.."
  until ssh $SSH_OPTS ec2-user@$IP "echo ok" &>/dev/null; do
    echo -n "."; sleep 5
  done
  echo " ??
done

echo "=============================="
echo " [3/3] k3s Frontend êµ¬ì„±"
echo "=============================="
ssh $SSH_OPTS ec2-user@$FRONTEND_IP 'sudo bash -s' < "$LAB_ROOT/scripts/system/01_k3s_frontend.sh"
scp -O $SSH_OPTS -r "$LAB_ROOT/manifests" ec2-user@$FRONTEND_IP:~/

cat > "$LAB_ROOT/ADDRESS.md" <<EOF
# k3s-storage-lab ?‘ì† ?•ë³´

## Frontend (k3s server)
\`\`\`
ssh -i /home/psi/.ssh/storage-lab.pem -o StrictHostKeyChecking=no ec2-user@${FRONTEND_IP}
\`\`\`

## Backend (Ceph + BeeGFS)
\`\`\`
ssh -i /home/psi/.ssh/storage-lab.pem -o StrictHostKeyChecking=no ec2-user@${BACKEND_IP}
\`\`\`
EOF
echo "  ?‘ì† ?•ë³´ ?€???„ë£Œ: $LAB_ROOT/ADDRESS.md"

echo ""
echo "??Stage 1 ?„ë£Œ ???¸í”„??+ k3s êµ¬ì„±??
echo "  ?¤ìŒ ?¨ê³„: bash scripts/lifecycle/start_2_ceph.sh"
