#!/bin/bash
# Rollback Stage 3: BeeGFS CSI ?úÍ±∞ ??BeeGFS Î∞±Ïóî???ïÎ¶¨
# ?§Ìñâ ?úÏÑú: rollback_3_beegfs.sh ??rollback_2_ceph.sh ??rollback_1_infra.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAB_ENV="$LAB_ROOT/lab.env"

if [ ! -f "$LAB_ENV" ]; then
  echo "??$LAB_ENV ?ÜÏùå ??Î°§Î∞±???ÅÌÉúÍ∞Ä ?ÜÏäµ?àÎã§."
  exit 1
fi
set -a; source "$LAB_ENV"; set +a

SSH_KEY="${SSH_KEY_PATH:-${SSH_KEY:-$HOME/.ssh/storage-lab.pem}}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [1/2] BeeGFS CSI ?úÍ±∞ (Frontend)"
echo "=============================="
ssh $SSH_OPTS ec2-user@$FRONTEND_IP 'sudo bash -s' <<'EOF'
export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"

kubectl delete namespace beegfs-csi --ignore-not-found
kubectl delete storageclass beegfs-scratch --ignore-not-found
echo "BeeGFS CSI ?úÍ±∞ ?ÑÎ£å"
EOF

echo "=============================="
echo " [2/2] BeeGFS Î∞±Ïóî???ïÎ¶¨ (Backend)"
echo "=============================="
ssh $SSH_OPTS ec2-user@$BACKEND_IP 'sudo bash -s' <<'EOF'
for svc in beegfs-storage beegfs-meta beegfs-mgmtd; do
  systemctl stop    "$svc" 2>/dev/null || true
  systemctl disable "$svc" 2>/dev/null || true
done

umount /mnt/beegfs/storage 2>/dev/null || true
lvremove -f /dev/beegfs-vg/beegfs-lv 2>/dev/null || true
vgremove -f beegfs-vg                2>/dev/null || true
PVS=$(pvs --noheadings -o pv_name --select vg_name=beegfs-vg 2>/dev/null || true)
[ -n "$PVS" ] && pvremove -ff -y $PVS 2>/dev/null || true

sed -i '/beegfs-vg/d' /etc/fstab 2>/dev/null || true
rm -rf /mnt/beegfs \
       /etc/beegfs/beegfs-mgmtd.toml \
       /etc/beegfs/beegfs-meta.conf \
       /etc/beegfs/beegfs-storage.conf
echo "BeeGFS Î∞±Ïóî???ïÎ¶¨ ?ÑÎ£å"
EOF

echo ""
echo "??Stage 3 Î°§Î∞± ?ÑÎ£å"
echo "  ?§Ïùå ?®Í≥Ñ (?ÑÏöî ??: bash scripts/lifecycle/rollback_2_ceph.sh"
