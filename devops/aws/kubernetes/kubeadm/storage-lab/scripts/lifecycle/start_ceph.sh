#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [0/4] ?¨Ï†Ñ ?îÍµ¨?¨Ìï≠ ?ïÏù∏"
echo "=============================="
MISSING=()
for cmd in tofu jq ssh scp; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING+=("$cmd")
  fi
done
if [ ! -f "$SSH_KEY" ]; then
  MISSING+=("ssh-key:$SSH_KEY")
fi
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "???ÑÎùΩ????™©: ${MISSING[*]}"
  exit 1
fi
echo "??Î™®Îì† ?ÑÏàò ??™© ?ïÏù∏ ?ÑÎ£å"

echo "=============================="
echo " [1/4] ?∏ÌîÑ???ïÎ≥¥ ?òÏßë"
echo "=============================="
cd "$LAB_ROOT/opentofu"
BASTION_IP=$(tofu output -raw bastion_public_ip)
MASTER_IP=$(tofu output -json master_private_ips | jq -r '.[0]')
WORKER_IPS=($(tofu output -json worker_private_ips | jq -r '.[]'))
cd "$LAB_ROOT"

echo "  Bastion : $BASTION_IP"
echo "  Master  : $MASTER_IP"
echo "  Workers : ${WORKER_IPS[*]}"

echo "=============================="
echo " [2/4] Bastion ?òÍ≤Ω Ï§ÄÎπ?
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP "rm -rf ~/scripts && mkdir -p ~/scripts"
scp -O $SSH_OPTS "$LAB_ROOT/scripts/system/ceph_install.sh" ubuntu@$BASTION_IP:~/scripts/

# .env ?ùÏÑ± (Î∞∞Ïä§Ï≤úÏóê??scripts/system/ceph_install.shÍ∞Ä Ï∞∏Ï°∞)
printf "SSH_KEY=\$HOME/.ssh/storage-lab.pem
M1_PUB=%s
M1_PRIV=%s
WORKER_PUBS=(%s)
WORKER_PRIVS=(%s)
" \
  "$MASTER_IP" "$MASTER_IP" \
  "${WORKER_IPS[*]}" "${WORKER_IPS[*]}" \
  | ssh $SSH_OPTS ubuntu@$BASTION_IP "cat > ~/scripts/.env"

# kubectl ?§Ïπò (Î∞∞Ïä§Ï≤úÏóê ?ÜÎäî Í≤ΩÏö∞)
ssh $SSH_OPTS ubuntu@$BASTION_IP "
  if ! command -v kubectl &>/dev/null; then
    echo '  kubectl ?§Ïπò Ï§?..'
    curl -sLO https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
    echo '  ??kubectl ?§Ïπò ?ÑÎ£å'
  else
    echo '  ??kubectl ?¥Î? ?§Ïπò??
  fi
"

echo "=============================="
echo " [3/4] Ceph ?¥Îü¨?§ÌÑ∞ Íµ¨ÏÑ± (Bastion?êÏÑú ?§Ìñâ)"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "export KUBECONFIG=~/.kube/config-k8s-storage-lab && cd ~ && bash scripts/ceph_install.sh"

echo "=============================="
echo " [4/4] ?àÎÇ¥"
echo "=============================="
echo ""
echo "???∏ÌîÑ?? K8s, Ceph(rook) Íµ¨ÏÑ± ?ÑÎ£å!"
echo "   StorageClass: ceph-rbd, ceph-cephfs"
echo "   kubeconfig  : ~/.kube/config-k8s-storage-lab (Î∞∞Ïä§Ï≤?"
echo ""
echo "?†Ô∏è  BeeGFS ?§Ïπò??Î≥ÑÎèÑ ?§Ìñâ ?ÑÏöî:"
echo "   1. bash scripts/lifecycle/start_beegfs.sh"
echo "   2. kubectl apply -f manifests/examples/test-pvc-beegfs.yaml"
echo ""
echo "   rook-cephÎß??¨ÏÑ§Ïπ??ÑÏöî ??"
echo "   bash scripts/lifecycle/destroy_ceph.sh && bash scripts/lifecycle/start_ceph.sh"
