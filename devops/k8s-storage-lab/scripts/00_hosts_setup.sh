#!/bin/bash
set -e
# 이 스크립트는 bastion에서 실행됩니다 (start_k8s.sh → Ansible로 대체됨)
# Ansible 없이 수동으로 /etc/hosts 및 SSH 키를 배포할 때 사용하세요.

source scripts/.env

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

WORKER_COUNT=${#WORKER_PUBS[@]}
ALL_PRIV=($M1_PRIV "${WORKER_PRIVS[@]}" $N1_PRIV $N2_PRIV)

echo "=============================="
echo " Step 0-1: 노드 부팅 대기"
echo "=============================="
for ip in "${ALL_PRIV[@]}"; do
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

for ip in "${ALL_PRIV[@]}"; do
  ssh $SSH_OPTS ubuntu@$ip "
    sudo sed -i '/# k8s-storage-lab/,/^$/d' /etc/hosts
    printf '$HOSTS_LINES\n' | sudo tee -a /etc/hosts > /dev/null
  "
  echo "  /etc/hosts 업데이트: $ip"
done

echo "=============================="
echo " Step 0-3: 클러스터 내부 SSH 키 생성 및 배포"
echo "=============================="
$CSSH$M1_PRIV "[ -f ~/.ssh/id_rsa ] || ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -q"
CLUSTER_PUBKEY=$($CSSH$M1_PRIV "cat ~/.ssh/id_rsa.pub")

for ip in "${ALL_PRIV[@]}"; do
  ssh $SSH_OPTS ubuntu@$ip "
    grep -qF '$CLUSTER_PUBKEY' ~/.ssh/authorized_keys 2>/dev/null || \
      echo '$CLUSTER_PUBKEY' >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
  "
  echo "  SSH 키 배포: $ip"
done

echo ""
echo "✅ Step 0 완료 - 다음: scripts/01_k8s_install.sh"
