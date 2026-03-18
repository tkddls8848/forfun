#!/bin/bash
set -e
source scripts/.env 2>/dev/null || true

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
SNAPSHOT_MODE="${1:-snapshot}"

cd opentofu/

if [ "$SNAPSHOT_MODE" = "snapshot" ]; then
  echo "=============================="
  echo " EBS 스냅샷 생성"
  echo "=============================="
  aws ec2 describe-volumes \
    --region $AWS_REGION \
    --filters "Name=tag:Name,Values=*ceph-osd*" \
    --query 'Volumes[].VolumeId' \
    --output text | tr '\t' '\n' | while read vol_id; do
      echo "  스냅샷: $vol_id"
      aws ec2 create-snapshot \
        --region $AWS_REGION \
        --volume-id $vol_id \
        --description "k8s-storage-lab-backup-$(date +%Y%m%d)" \
        --query 'SnapshotId' --output text
  done

  echo "=============================="
  echo " EC2 중지"
  echo "=============================="
  aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "Name=tag:Name,Values=k8s-storage-lab-*" \
               "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text | tr '\t' '\n' | while read iid; do
      echo "  중지: $iid"
      aws ec2 stop-instances --region $AWS_REGION --instance-ids $iid
  done
  echo "✅ EC2 중지 완료"

elif [ "$SNAPSHOT_MODE" = "destroy" ]; then
  echo "⚠️  모든 리소스가 삭제됩니다. (yes/no)"
  read -r confirm
  if [ "$confirm" = "yes" ]; then
    tofu destroy -auto-approve
    echo "✅ 전체 삭제 완료"
  else
    echo "취소됨"
  fi
fi

cd ..
