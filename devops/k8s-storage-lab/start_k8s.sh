#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " [0/5] 사전 요구사항 확인"
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
  echo "❌ 누락된 항목: ${MISSING[*]}"
  for item in "${MISSING[@]}"; do
    case "$item" in
      tofu)      echo "  tofu    : https://opentofu.org/docs/intro/install/" ;;
      aws)       echo "  awscli  : pip3 install awscli --break-system-packages" ;;
      ssh|scp)   echo "  ssh/scp : sudo apt-get install -y openssh-client" ;;
      ssh-key:*) echo "  ssh key : ${item#ssh-key:} 파일이 없습니다" ;;
    esac
  done
  exit 1
fi
echo "✅ 모든 필수 항목 확인 완료"
echo ""

echo "=============================="
echo " [1/5] AWS 인프라 생성"
echo "=============================="
cd "$SCRIPT_DIR/opentofu"
tofu init
tofu apply -auto-approve

BASTION_IP=$(tofu output -raw bastion_public_ip)
echo ""
echo "  Bastion IP: $BASTION_IP"

echo "=============================="
echo " [2/5] Bastion SSH 대기"
echo "=============================="
echo -n "  연결 대기 중..."
until ssh $SSH_OPTS ubuntu@$BASTION_IP "echo ok" &>/dev/null; do
  echo -n "."; sleep 5
done
echo " ✓"

echo "=============================="
echo " [3/5] SSH 키 + Playbook 전송"
echo "=============================="
ssh $SSH_OPTS ubuntu@$BASTION_IP "mkdir -p ~/.ssh && chmod 700 ~/.ssh && rm -f ~/.ssh/storage-lab.pem"
scp $SSH_OPTS "$SSH_KEY" ubuntu@$BASTION_IP:~/.ssh/storage-lab.pem
ssh $SSH_OPTS ubuntu@$BASTION_IP "chmod 400 ~/.ssh/storage-lab.pem && rm -rf ~/ansible ~/manifests"
scp -O $SSH_OPTS -r "$SCRIPT_DIR/ansible"    ubuntu@$BASTION_IP:~/
scp -O $SSH_OPTS -r "$SCRIPT_DIR/manifests"  ubuntu@$BASTION_IP:~/

echo "=============================="
echo " [4/5] 나머지 노드 부팅 대기"
echo "=============================="
NODE_IPS=$(
  tofu output -json master_private_ips | jq -r '.[]'
  tofu output -json worker_private_ips | jq -r '.[]'
  tofu output -json nsd_private_ips    | jq -r '.[]'
)
for IP in $NODE_IPS; do
  echo -n "  $IP 대기 중..."
  until ssh $SSH_OPTS -o "ProxyCommand=ssh $SSH_OPTS -W %h:%p ubuntu@$BASTION_IP" ubuntu@$IP "echo ok" &>/dev/null; do
    echo -n "."; sleep 5
  done
  echo " ✓"
done

echo "=============================="
echo " [5/5] Ansible Playbook 실행 (Bastion)"
echo "=============================="
LOCK_FILE="/tmp/k8s-setup.lock"
ssh $SSH_OPTS ubuntu@$BASTION_IP \
  "while [ ! -f /tmp/ansible-ready ]; do echo 'Waiting for ansible install...'; sleep 10; done && \
   if [ -f $LOCK_FILE ]; then \
     echo '❌ 이미 다른 프로세스가 실행 중입니다 (lock: $LOCK_FILE)'; \
     exit 1; \
   fi && \
   touch $LOCK_FILE && \
   trap 'rm -f $LOCK_FILE' EXIT && \
   cd ~/ansible && /home/ubuntu/.local/bin/ansible-playbook \
     -i inventory/aws_ec2.yml playbooks/k8s.yml && \
   touch /tmp/ansible-k8s-complete && \
   rm -f $LOCK_FILE"

echo ""
echo "✅ 완료"
echo "   Bastion : ssh -i $SSH_KEY ubuntu@$BASTION_IP"
echo "   Bastion에서 내부 노드 접근: ssh ubuntu@<PRIVATE_IP>"
echo "   kubeconfig: ~/.kube/config-k8s-storage-lab"
echo ""
echo "⚠️  주의: scripts/ 디렉토리의 스크립트는 Ansible 완료 후 실행하세요"
