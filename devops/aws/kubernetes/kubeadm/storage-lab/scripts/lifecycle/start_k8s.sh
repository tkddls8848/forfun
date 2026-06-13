#!/bin/bash
# USE_PACKER_AMI=true: Packer ?¨Ï†Ñ ÎπåÎìú AMI ?¨Ïö© (?®ÌÇ§ÏßÄ ?§Ïπò ?®Í≥Ñ ?§ÌÇµ --skip-tags ami_base)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"
USE_PACKER_AMI=${USE_PACKER_AMI:-false}

echo "=============================="
echo " [0/5] ?¨Ï†Ñ ?îÍµ¨?¨Ìï≠ ?ïÏù∏"
echo "=============================="
MISSING=()
for cmd in tofu aws ssh scp; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING+=("$cmd")
  fi
done
if [ ! -f "$SSH_KEY" ]; then
  MISSING+=("ssh-key:$SSH_KEY")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "???ÑÎùΩ????™©: ${MISSING[*]}"
  for item in "${MISSING[@]}"; do
    case "$item" in
      tofu)      echo "  tofu    : https://opentofu.org/docs/intro/install/" ;;
      aws)       echo "  awscli  : pip3 install awscli --break-system-packages" ;;
      ssh|scp)   echo "  ssh/scp : sudo apt-get install -y openssh-client" ;;
      ssh-key:*) echo "  ssh key : ${item#ssh-key:} ?åÏùº???ÜÏäµ?àÎã§" ;;
    esac
  done
  exit 1
fi
echo "??Î™®Îì† ?ÑÏàò ??™© ?ïÏù∏ ?ÑÎ£å"
echo ""

echo "=============================="
echo " [1/5] AWS ?∏ÌîÑ???ùÏÑ±"
echo "=============================="
cd "$LAB_ROOT/opentofu"
tofu init
tofu apply -auto-approve

BASTION_IP=$(tofu output -raw bastion_public_ip)
BASTION_PRIVATE_IP=$(tofu output -raw bastion_private_ip)
echo ""
echo "  Bastion Public IP  : $BASTION_IP"
echo "  Bastion Private IP : $BASTION_PRIVATE_IP (HAProxy endpoint)"

echo "=============================="
echo " [2/5] Bastion SSH ?ÄÍ∏?
echo "=============================="
echo -n "  ?∞Í≤∞ ?ÄÍ∏?Ï§?.."
until ssh $SSH_OPTS ubuntu@$BASTION_IP "echo ok" &>/dev/null; do
  echo -n "."; sleep 5
done
echo " ??

echo "=============================="
echo " [3/5] SSH ??+ Playbook ?ÑÏÜ°"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP "mkdir -p ~/.ssh && chmod 700 ~/.ssh && rm -f ~/.ssh/storage-lab.pem"
scp $SSH_OPTS "$SSH_KEY" ubuntu@$BASTION_IP:~/.ssh/storage-lab.pem
ssh $SSH_OPTS ubuntu@$BASTION_IP "chmod 400 ~/.ssh/storage-lab.pem && rm -rf ~/ansible ~/manifests"
scp -O $SSH_OPTS -r "$LAB_ROOT/ansible"    ubuntu@$BASTION_IP:~/
scp -O $SSH_OPTS -r "$LAB_ROOT/manifests"  ubuntu@$BASTION_IP:~/

echo "=============================="
echo " [4/5] ?òÎ®∏ÏßÄ ?∏Îìú Î∂Ä???ÄÍ∏?
echo "=============================="
NODE_IPS=$(
  tofu output -json master_private_ips | jq -r '.[]'
  tofu output -json worker_private_ips | jq -r '.[]'
)
for IP in $NODE_IPS; do
  echo -n "  $IP ?ÄÍ∏?Ï§?.."
  until ssh $SSH_OPTS -o "ProxyCommand=ssh $SSH_OPTS -W %h:%p ubuntu@$BASTION_IP" ubuntu@$IP "echo ok" &>/dev/null; do
    echo -n "."; sleep 5
  done
  echo " ??
done

echo "=============================="
echo " [5/5] Ansible Playbook ?§Ìñâ (Bastion)"
echo "=============================="
LOCK_FILE="/tmp/k8s-setup.lock"
if [ "$USE_PACKER_AMI" = "true" ]; then
  ANSIBLE_EXTRA_ARGS="--skip-tags ami_base"
  echo "  [Packer AMI] --skip-tags ami_base ?ÅÏö© (?®ÌÇ§ÏßÄ ?§Ïπò ?®Í≥Ñ ?§ÌÇµ)"
else
  ANSIBLE_EXTRA_ARGS=""
fi
ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "while [ ! -f /tmp/ansible-ready ]; do echo 'Waiting for ansible install...'; sleep 10; done && \
   if [ -f $LOCK_FILE ]; then \
     echo '???¥Î? ?§Î•∏ ?ÑÎ°ú?∏Ïä§Í∞Ä ?§Ìñâ Ï§ëÏûÖ?àÎã§ (lock: $LOCK_FILE)'; \
     exit 1; \
   fi && \
   touch $LOCK_FILE && \
   trap 'rm -f $LOCK_FILE' EXIT && \
   cd ~/ansible && /home/ubuntu/.local/bin/ansible-playbook \
     -i inventory/aws_ec2.yml playbooks/k8s.yml \
     --extra-vars \"control_plane_endpoint=$BASTION_PRIVATE_IP\" \
     $ANSIBLE_EXTRA_ARGS && \
   touch /tmp/ansible-k8s-complete && \
   rm -f $LOCK_FILE"

echo ""
echo "???ÑÎ£å"
echo "   Bastion     : ssh -i $SSH_KEY ubuntu@$BASTION_IP"
echo "   HAProxy     : http://$BASTION_IP:9000/stats  (admin/admin)"
echo "   kubeconfig  : ~/.kube/config-k8s-storage-lab (Î∞∞Ïä§Ï≤?"
echo ""
echo "   ?§Ïùå ?®Í≥Ñ:"
echo "   1. bash scripts/lifecycle/start_ceph.sh    # Ceph(rook) ?§Ïπò"
echo "   2. bash scripts/lifecycle/start_beegfs.sh  # BeeGFS ?§Ïπò"
