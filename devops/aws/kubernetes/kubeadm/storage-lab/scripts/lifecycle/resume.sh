#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
TAG_FILTER="Name=tag:Name,Values=k8s-storage-lab-*"

echo "=============================="
echo " EC2 ?úÏûë"
echo "=============================="
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "$TAG_FILTER" "Name=instance-state-name,Values=stopped" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text | tr '\t' ' ')

if [ -z "$INSTANCE_IDS" ]; then
  echo "  Ï§ëÏ????∏Ïä§?¥Ïä§Í∞Ä ?ÜÏäµ?àÎã§."
  aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "$TAG_FILTER" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],State.Name,PublicIpAddress,PrivateIpAddress]' \
    --output table
  exit 0
fi

echo "  ?úÏûë ?Ä?? $INSTANCE_IDS"
aws ec2 start-instances --region $AWS_REGION --instance-ids $INSTANCE_IDS > /dev/null

echo -n "  ?§Ìñâ ?ÄÍ∏?Ï§?.."
aws ec2 wait instance-running --region $AWS_REGION --instance-ids $INSTANCE_IDS
echo " ??

sleep 10  # IP ?†Îãπ ?àÏ†ï???ÄÍ∏?
echo "=============================="
echo " Bastion IP Í∞±Ïã†"
echo "=============================="
BASTION_IP=$(tofu -chdir="$LAB_ROOT/opentofu" output -raw bastion_public_ip)
BASTION_PRIVATE_IP=$(tofu -chdir="$LAB_ROOT/opentofu" output -raw bastion_private_ip)
echo "  Bastion Public  : $BASTION_IP"
echo "  Bastion Private : $BASTION_PRIVATE_IP"

echo "=============================="
echo " Bastion SSH ?ÄÍ∏?
echo "=============================="
echo -n "  ?∞Í≤∞ ?ÄÍ∏?Ï§?.."
until ssh $SSH_OPTS ubuntu@$BASTION_IP "echo ok" &>/dev/null; do
  echo -n "."; sleep 5
done
echo " ??

echo "=============================="
echo " Playbook ?¨Ï†Ñ??(ÏµúÏã† ?ÅÌÉú Î∞òÏòÅ)"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP "rm -rf ~/ansible ~/manifests"
scp -O $SSH_OPTS -r "$LAB_ROOT/ansible"   ubuntu@$BASTION_IP:~/
scp -O $SSH_OPTS -r "$LAB_ROOT/manifests" ubuntu@$BASTION_IP:~/

echo ""
echo "=============================="
echo " ?ÑÏû¨ ?∏Îìú ?ÅÌÉú"
echo "=============================="
aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "$TAG_FILTER" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],PrivateIpAddress,State.Name]' \
  --output table

echo ""
echo "???¨Ïãú???ÑÎ£å"
echo "   Bastion : ssh -i $SSH_KEY ubuntu@$BASTION_IP"
echo ""
echo "   K8s ?åÎ†à?¥Î∂Å ?¨Ïã§???ÑÏöî ??(bastion?êÏÑú):"
echo "   cd ~/ansible && /home/ubuntu/.local/bin/ansible-playbook \\"
echo "     -i inventory/aws_ec2.yml playbooks/k8s.yml \\"
echo "     --extra-vars \"control_plane_endpoint=$BASTION_PRIVATE_IP\""
