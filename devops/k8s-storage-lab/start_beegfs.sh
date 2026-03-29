#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [0/4] 사전 요구사항 확인"
echo "=============================="
MISSING=()
for cmd in tofu ssh scp; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING+=("$cmd")
  fi
done
if [ ! -f "$SSH_KEY" ]; then
  MISSING+=("ssh-key:$SSH_KEY")
fi
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "❌ 누락된 항목: ${MISSING[*]}"
  exit 1
fi
echo "✅ 모든 필수 항목 확인 완료"

echo "=============================="
echo " [1/4] 인프라 정보 수집"
echo "=============================="
cd "$SCRIPT_DIR/opentofu"
BASTION_IP=$(tofu output -raw bastion_public_ip)
cd "$SCRIPT_DIR"
echo "  Bastion : $BASTION_IP"

echo "=============================="
echo " [2/4] Bastion 환경 준비"
echo "=============================="
scp -O $SSH_OPTS -r "$SCRIPT_DIR/ansible"    ubuntu@$BASTION_IP:~/
scp -O $SSH_OPTS -r "$SCRIPT_DIR/manifests"  ubuntu@$BASTION_IP:~/
echo "  ✅ 파일 전송 완료"

echo "=============================="
echo " [3/4] BeeGFS 설치 (Bastion Ansible 실행)"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "cd ~/ansible && /home/ubuntu/.local/bin/ansible-playbook \
     -i inventory/aws_ec2.yml playbooks/beegfs.yml"

echo "=============================="
echo " [4/4] 완료"
echo "=============================="
echo ""
echo "✅ BeeGFS 설치 완료!"
echo "   StorageClass     : beegfs-scratch"
echo "   BeeGFS 파드      : kubectl get pods -n beegfs-system"
echo "   Prometheus 메트릭: http://<exporter-svc>:9100/metrics"
echo "   Grafana 대시보드 : BeeGFS Overview (자동 import)"
echo "   kubeconfig       : ~/.kube/config-k8s-storage-lab (배스천)"
echo ""
echo "   PVC 테스트:"
echo "   kubectl apply -f manifests/test-pvc/test-pvc-beegfs.yaml"
echo ""
echo "   BeeGFS 재설치 필요 시:"
echo "   bash destroy_beegfs.sh && bash start_beegfs.sh"
