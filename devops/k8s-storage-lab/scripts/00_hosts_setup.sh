#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

export SSH_KEY="${SSH_KEY_PATH:-$HOME/.ssh/storage-lab.pem}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " Step 0: IP 수집 (tofu output)"
echo "=============================="

M1_PUB=$(tofu -chdir=opentofu output -json master_public_ips  | jq -r '.[0]')
M1_PRIV=$(tofu -chdir=opentofu output -json master_private_ips | jq -r '.[0]')

# 워커 수를 tofu output에서 동적으로 수집
WORKER_COUNT=$(tofu -chdir=opentofu output -json worker_public_ips | jq 'length')
WORKER_PUBS=()
WORKER_PRIVS=()
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  WORKER_PUBS+=($(tofu -chdir=opentofu output -json worker_public_ips  | jq -r ".[$i]"))
  WORKER_PRIVS+=($(tofu -chdir=opentofu output -json worker_private_ips | jq -r ".[$i]"))
done

N1_PUB=$(tofu -chdir=opentofu output -json nsd_public_ips  | jq -r '.[0]')
N2_PUB=$(tofu -chdir=opentofu output -json nsd_public_ips  | jq -r '.[1]')
N1_PRIV=$(tofu -chdir=opentofu output -json nsd_private_ips | jq -r '.[0]')
N2_PRIV=$(tofu -chdir=opentofu output -json nsd_private_ips | jq -r '.[1]')

ALL_PUB=($M1_PUB "${WORKER_PUBS[@]}" $N1_PUB $N2_PUB)

# .env 생성 (배열 포함)
{
  echo "M1_PUB=$M1_PUB"
  echo "M1_PRIV=$M1_PRIV"
  echo "WORKER_PUBS=(${WORKER_PUBS[*]})"
  echo "WORKER_PRIVS=(${WORKER_PRIVS[*]})"
  echo "N1_PUB=$N1_PUB; N2_PUB=$N2_PUB"
  echo "N1_PRIV=$N1_PRIV; N2_PRIV=$N2_PRIV"
  echo "SSH_KEY=$SSH_KEY"
} > scripts/.env

echo "  수집된 워커: ${WORKER_PUBS[*]}"

echo "=============================="
echo " Step 0-1: 노드 부팅 대기"
echo "=============================="
for ip in "${ALL_PUB[@]}"; do
  echo -n "  $ip 대기 중..."
  until ssh $SSH_OPTS ubuntu@$ip "echo ok" &>/dev/null; do
    echo -n "."; sleep 5
  done
  echo " ✓"
done

echo "=============================="
echo " Step 0-2: /etc/hosts 배포"
echo "=============================="
HOSTS_LINES="# k8s-storage-lab\n$M1_PRIV  master-1"
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  HOSTS_LINES+="\n${WORKER_PRIVS[$i]}  worker-$((i + 1))"
done
HOSTS_LINES+="\n$N1_PRIV  nsd-1\n$N2_PRIV  nsd-2"

for ip in "${ALL_PUB[@]}"; do
  ssh $SSH_OPTS ubuntu@$ip "printf '$HOSTS_LINES\n' | sudo tee -a /etc/hosts > /dev/null"
  echo "  /etc/hosts 업데이트: $ip"
done

echo "=============================="
echo " Step 0-3: 클러스터 내부 SSH 키 생성 및 배포"
echo "=============================="
ssh $SSH_OPTS ubuntu@$M1_PUB "
  [ -f ~/.ssh/id_rsa ] || ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -q
"
CLUSTER_PUBKEY=$(ssh $SSH_OPTS ubuntu@$M1_PUB "cat ~/.ssh/id_rsa.pub")

for ip in "${ALL_PUB[@]}"; do
  ssh $SSH_OPTS ubuntu@$ip "
    echo '$CLUSTER_PUBKEY' >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
  "
  echo "  SSH 키 배포: $ip"
done

echo ""
echo "✅ Step 0 완료 - 다음: scripts/01_k8s_install.sh"
