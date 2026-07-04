#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [0/4] ?¬μ „ ?”κµ¬?¬ν•­ ?•μΈ"
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
  echo "???„λ½????ª©: ${MISSING[*]}"
  exit 1
fi
echo "??λª¨λ“  ?„μ ??ª© ?•μΈ ?„λ£"

echo "=============================="
echo " [1/4] ?Έν”„???•λ³΄ ?μ§‘"
echo "=============================="
cd "$LAB_ROOT/opentofu"
BASTION_IP=$(tofu output -raw bastion_public_ip)
cd "$LAB_ROOT"
echo "  Bastion : $BASTION_IP"

echo "=============================="
echo " [2/4] Bastion ?κ²½ μ¤€λΉ?
echo "=============================="
scp -O $SSH_OPTS -r "$LAB_ROOT/ansible"    ubuntu@$BASTION_IP:~/
scp -O $SSH_OPTS -r "$LAB_ROOT/manifests"  ubuntu@$BASTION_IP:~/
echo "  ???μΌ ?„μ†΅ ?„λ£"

echo "=============================="
echo " [3/4] BeeGFS ?¤μΉ (Bastion Ansible ?¤ν–‰)"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "cd ~/ansible && /home/ubuntu/.local/bin/ansible-playbook \
     -i inventory/aws_ec2.yml playbooks/beegfs.yml"

echo "=============================="
echo " [4/4] ?„λ£"
echo "=============================="
echo ""
echo "??BeeGFS ?¤μΉ ?„λ£!"
echo "   StorageClass     : beegfs-scratch"
echo "   BeeGFS ?λ“      : kubectl get pods -n beegfs-system"
echo "   Prometheus λ©”νΈλ¦? http://<exporter-svc>:9100/metrics"
echo "   Grafana ?€?λ³΄??: BeeGFS Overview (?λ™ import)"
echo "   kubeconfig       : ~/.kube/config-k8s-storage-lab (λ°°μ¤μ²?"
echo ""
echo "   PVC ?μ¤??"
echo "   kubectl apply -f manifests/examples/test-pvc-beegfs.yaml"
echo ""
echo "   BeeGFS ?¬μ„¤μΉ??„μ” ??"
echo "   bash scripts/lifecycle/destroy_beegfs.sh && bash scripts/lifecycle/start_beegfs.sh"
