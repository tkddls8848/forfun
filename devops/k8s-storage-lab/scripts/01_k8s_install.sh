#!/bin/bash
set -e

# Lock 파일 확인 - Ansible과 동시 실행 방지
LOCK_FILE="/tmp/k8s-setup.lock"
if [ -f "$LOCK_FILE" ]; then
  echo "❌ 다른 프로세스가 K8s 설정 중입니다 (lock: $LOCK_FILE)"
  echo "   Ansible playbook 또는 다른 스크립트가 실행 중입니다."
  exit 1
fi

# Ansible 완료 확인
if [ -f "/tmp/ansible-k8s-complete" ]; then
  echo "⚠️  Ansible로 이미 K8s 클러스터가 구성되었습니다."
  echo "   이 스크립트는 Ansible을 사용하지 않은 경우에만 실행하세요."
  read -p "계속 진행하시겠습니까? (yes/no): " answer
  if [ "$answer" != "yes" ]; then
    echo "종료합니다."
    exit 0
  fi
fi

source scripts/.env

SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

K8S_VERSION="1.31"
POD_CIDR="10.244.0.0/16"   # Flannel 기본 CIDR

# Lock 파일 생성 및 trap 설정
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

WORKER_COUNT=${#WORKER_PUBS[@]}
ALL_K8S_PUB=($M1_PUB "${WORKER_PUBS[@]}")
ALL_K8S_PRIV=($M1_PRIV "${WORKER_PRIVS[@]}")

echo "=============================="
echo " Step 4-0: 노드 hostname 설정"
echo "=============================="
# kubeadm은 hostname을 노드명으로 등록하므로 미리 설정
$CSSH$M1_PUB "sudo hostnamectl set-hostname master-1"
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  $CSSH${WORKER_PUBS[$i]} "sudo hostnamectl set-hostname worker-$((i + 1))"
  echo "  ✓ hostname: worker-$((i + 1))"
done

echo "=============================="
echo " Step 4: kubeadm 설치 (전체 노드)"
echo "=============================="
# AWS EC2: user_data(부트스트랩) 완료 대기 - SSH 가능해도 apt install 중일 수 있음
# 커널 업데이트 시 user_data 내부에서 reboot 발생 가능 → SSH 재연결 확인까지 대기
for ip in "${ALL_K8S_PUB[@]}"; do
  echo "  cloud-init 완료 대기: $ip"
  $CSSH$ip "cloud-init status --wait" || true
  echo -n "  SSH 재연결 확인: $ip"
  until ssh $SSH_OPTS ubuntu@$ip "echo ok" &>/dev/null; do
    echo -n "."; sleep 5
  done
  echo " ✓"
done

for ip in "${ALL_K8S_PUB[@]}"; do
  $CSSH$ip <<EOF
    sudo apt-get update -y
    sudo apt-get install -y apt-transport-https ca-certificates curl gpg

    curl -fsSL https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/Release.key | \
      sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
      https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/ /" | \
      sudo tee /etc/apt/sources.list.d/kubernetes.list

    sudo apt-get update -y
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    sudo systemctl enable --now kubelet
EOF
  echo "  ✓ kubeadm 설치: $ip"
done

echo "=============================="
echo " Step 4-1: Master-1 초기화"
echo "=============================="
# Ubuntu 24.04는 nftables 네이티브 → kube-proxy를 nftables 모드로 강제 지정
# iptables 모드(기본값)는 Flannel과 lock 경합 → 전체 클러스터 네트워킹 붕괴
$CSSH$M1_PUB "
cat <<'EOF' | sudo tee /tmp/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
networking:
  podSubnet: $POD_CIDR
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: \"nftables\"
EOF

  sudo kubeadm init \
    --node-name master-1 \
    --config /tmp/kubeadm-config.yaml \
    --v=5 2>&1 | tee /tmp/kubeadm-init.log

  mkdir -p \$HOME/.kube
  sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config
  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
"

# kubeadm init은 동기 완료이나 API server가 완전히 서빙 상태가 될 때까지 대기
echo "  API server 준비 대기 (최대 2분)..."
$CSSH$M1_PUB "
  for i in \$(seq 1 24); do
    if kubectl cluster-info &>/dev/null; then
      echo \"  [\$i/24] API server 준비 완료\"
      break
    fi
    echo \"  [\$i/24] API server 대기 중...\"
    sleep 5
  done
"

# kube-proxy ConfigMap에서 nftables 모드 적용 확인
echo "  kube-proxy nftables 모드 검증..."
$CSSH$M1_PUB "
  MODE=\$(kubectl -n kube-system get configmap kube-proxy -o jsonpath='{.data.config\.conf}' \
    | grep '^mode:' | awk '{print \$2}' | tr -d '\"')
  if [ \"\$MODE\" = 'nftables' ]; then
    echo \"  ✅ kube-proxy mode: nftables 확인\"
  else
    echo \"  ⚠️  kube-proxy mode: '\$MODE' → nftables로 강제 패치\"
    kubectl -n kube-system get configmap kube-proxy -o yaml \
      | sed 's/mode: \"\"/mode: \"nftables\"/' \
      | kubectl apply -f -
  fi
"

echo "=============================="
echo " Step 4-2: Worker join 명령어 추출"
echo "=============================="
WORKER_JOIN=$($CSSH$M1_PUB "sudo kubeadm token create --print-join-command")

echo "=============================="
echo " Step 4-3: Worker 노드 join (순차)"
echo "=============================="
# 동시 join 시 API server/etcd 과부하 방지 → 노드 등록 확인 후 다음 join
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  NODE_NAME="worker-$((i + 1))"
  NODE_IP="${WORKER_PUBS[$i]}"
  $CSSH$NODE_IP "sudo $WORKER_JOIN --node-name $NODE_NAME"
  echo "  ✓ Worker join: $NODE_NAME"
  $CSSH$M1_PUB "
    for j in \$(seq 1 24); do
      kubectl get node $NODE_NAME &>/dev/null && echo '  $NODE_NAME 등록 확인' && break
      echo \"  [\$j/24] $NODE_NAME 등록 대기...\"; sleep 5
    done
  "
done

echo "=============================="
echo " Step 4-4: Flannel CNI (VXLAN 모드)"
echo "=============================="
# Flannel은 VXLAN(UDP 8472) 사용 → AWS SG 문제 없음
$CSSH$M1_PUB "kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"

echo "  Flannel Pod 기동 대기 (최대 5분)..."
$CSSH$M1_PUB "
  for i in \$(seq 1 60); do
    READY=\$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)
    TOTAL=\$(kubectl get nodes --no-headers 2>/dev/null | grep -c '.' || true)
    echo \"  [\$i/60] Ready: \$READY/\$TOTAL\"
    [ \"\$READY\" -gt 0 ] && [ \"\$READY\" -eq \"\$TOTAL\" ] && break
    sleep 5
  done
  kubectl get nodes -o wide
"

echo "=============================="
echo " Step 4-5: Worker 노드 레이블"
echo "=============================="
WORKER_NAMES=""
for i in $(seq 1 $WORKER_COUNT); do WORKER_NAMES+=" worker-$i"; done
$CSSH$M1_PUB "
  kubectl label nodes $WORKER_NAMES role=worker
  kubectl get nodes --show-labels
"

echo "=============================="
echo " Step 4-6: kubeconfig 로컬 저장"
echo "=============================="
mkdir -p ~/.kube
scp $SSH_OPTS ubuntu@$M1_PUB:~/.kube/config ~/.kube/config-k8s-storage-lab
echo ""
echo "✅ Step 4 완료 - kubeconfig → ~/.kube/config-k8s-storage-lab"
echo "   다음: scripts/02_ceph_install.sh"
