#!/bin/bash
set -e
cd "$(dirname "$0")/.."

export SSH_KEY="${SSH_KEY_PATH:-~/.ssh/id_rsa}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " Step 0: IP 수집 (tofu output)"
echo "=============================="

M1_PUB=$(tofu -chdir=opentofu output -json master_public_ips  | jq -r '.[0]')
M2_PUB=$(tofu -chdir=opentofu output -json master_public_ips  | jq -r '.[1]')
M3_PUB=$(tofu -chdir=opentofu output -json master_public_ips  | jq -r '.[2]')
W1_PUB=$(tofu -chdir=opentofu output -json worker_public_ips  | jq -r '.[0]')
W2_PUB=$(tofu -chdir=opentofu output -json worker_public_ips  | jq -r '.[1]')
W3_PUB=$(tofu -chdir=opentofu output -json worker_public_ips  | jq -r '.[2]')
N1_PUB=$(tofu -chdir=opentofu output -json nsd_public_ips     | jq -r '.[0]')
N2_PUB=$(tofu -chdir=opentofu output -json nsd_public_ips     | jq -r '.[1]')
C1_PUB=$(tofu -chdir=opentofu output -json ceph_public_ips    | jq -r '.[0]')
C2_PUB=$(tofu -chdir=opentofu output -json ceph_public_ips    | jq -r '.[1]')
C3_PUB=$(tofu -chdir=opentofu output -json ceph_public_ips    | jq -r '.[2]')

M1_PRIV=$(tofu -chdir=opentofu output -json master_private_ips | jq -r '.[0]')
M2_PRIV=$(tofu -chdir=opentofu output -json master_private_ips | jq -r '.[1]')
M3_PRIV=$(tofu -chdir=opentofu output -json master_private_ips | jq -r '.[2]')
W1_PRIV=$(tofu -chdir=opentofu output -json worker_private_ips | jq -r '.[0]')
W2_PRIV=$(tofu -chdir=opentofu output -json worker_private_ips | jq -r '.[1]')
W3_PRIV=$(tofu -chdir=opentofu output -json worker_private_ips | jq -r '.[2]')
N1_PRIV=$(tofu -chdir=opentofu output -json nsd_private_ips    | jq -r '.[0]')
N2_PRIV=$(tofu -chdir=opentofu output -json nsd_private_ips    | jq -r '.[1]')
C1_PRIV=$(tofu -chdir=opentofu output -json ceph_private_ips   | jq -r '.[0]')
C2_PRIV=$(tofu -chdir=opentofu output -json ceph_private_ips   | jq -r '.[1]')
C3_PRIV=$(tofu -chdir=opentofu output -json ceph_private_ips   | jq -r '.[2]')

ALL_PUB=($M1_PUB $M2_PUB $M3_PUB $W1_PUB $W2_PUB $W3_PUB $N1_PUB $N2_PUB $C1_PUB $C2_PUB $C3_PUB)

cat > scripts/.env <<EOF
M1_PUB=$M1_PUB; M2_PUB=$M2_PUB; M3_PUB=$M3_PUB
W1_PUB=$W1_PUB; W2_PUB=$W2_PUB; W3_PUB=$W3_PUB
N1_PUB=$N1_PUB; N2_PUB=$N2_PUB
C1_PUB=$C1_PUB; C2_PUB=$C2_PUB; C3_PUB=$C3_PUB
M1_PRIV=$M1_PRIV; M2_PRIV=$M2_PRIV; M3_PRIV=$M3_PRIV
W1_PRIV=$W1_PRIV; W2_PRIV=$W2_PRIV; W3_PRIV=$W3_PRIV
N1_PRIV=$N1_PRIV; N2_PRIV=$N2_PRIV
C1_PRIV=$C1_PRIV; C2_PRIV=$C2_PRIV; C3_PRIV=$C3_PRIV
SSH_KEY=$SSH_KEY
EOF

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
HOSTS=$(cat <<EOF
# k8s-storage-lab
$M1_PRIV  master-1
$M2_PRIV  master-2
$M3_PRIV  master-3
$W1_PRIV  worker-1
$W2_PRIV  worker-2
$W3_PRIV  worker-3
$N1_PRIV  nsd-1
$N2_PRIV  nsd-2
$C1_PRIV  ceph-1
$C2_PRIV  ceph-2
$C3_PRIV  ceph-3
EOF
)

for ip in "${ALL_PUB[@]}"; do
  ssh $SSH_OPTS ubuntu@$ip "echo '$HOSTS' | sudo tee -a /etc/hosts > /dev/null"
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
echo "✅ Step 0 완료 - 다음: scripts/01_ceph_install.sh"
