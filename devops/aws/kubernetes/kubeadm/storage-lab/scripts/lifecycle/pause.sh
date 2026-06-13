#!/bin/bash
set -e

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
TAG_FILTER="Name=tag:Name,Values=k8s-storage-lab-*"

echo "=============================="
echo " Ceph OSD EBS ?¤ëƒ…???ì„±"
echo "=============================="
aws ec2 describe-volumes \
  --region $AWS_REGION \
  --filters "Name=tag:Name,Values=*ceph-osd*" \
  --query 'Volumes[].VolumeId' \
  --output text | tr '\t' '\n' | while read vol_id; do
    [ -z "$vol_id" ] && continue
    echo "  ?¤ëƒ…?? $vol_id"
    aws ec2 create-snapshot \
      --region $AWS_REGION \
      --volume-id $vol_id \
      --description "k8s-storage-lab-backup-$(date +%Y%m%d)" \
      --query 'SnapshotId' --output text
done

echo "=============================="
echo " EC2 ì¤‘ì?"
echo "=============================="
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "$TAG_FILTER" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text | tr '\t' ' ')

if [ -z "$INSTANCE_IDS" ]; then
  echo "  ?¤í–‰ ì¤‘ì¸ ?¸ìŠ¤?´ìŠ¤ê°€ ?†ìŠµ?ˆë‹¤."
  exit 0
fi

echo "  ì¤‘ì? ?€?? $INSTANCE_IDS"
aws ec2 stop-instances --region $AWS_REGION --instance-ids $INSTANCE_IDS > /dev/null

echo -n "  ì¤‘ì? ?€ê¸?ì¤?.."
aws ec2 wait instance-stopped --region $AWS_REGION --instance-ids $INSTANCE_IDS
echo " ??

echo "???¤ëƒ…???ì„± ë°?EC2 ì¤‘ì? ?„ë£Œ (?¬ì‹œ?? bash scripts/lifecycle/resume.sh)"
