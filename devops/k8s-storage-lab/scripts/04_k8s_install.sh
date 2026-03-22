#!/bin/bash
set -e
source scripts/.env

SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

K8S_VERSION="1.29"
POD_CIDR="10.244.0.0/16"   # Flannel 기본 CIDR

ALL_K8S_PUB=($M1_PUB $W1_PUB $W2_PUB $W3_PUB $W4_PUB)

echo "=============================="
echo " Step 4-0: 노드 hostname 설정"
echo "=============================="
# kubeadm은 hostname을 노드명으로 등록하므로 미리 설정
$CSSH$M1_PUB "sudo hostnamectl set-hostname master-1"
$CSSH$W1_PUB "sudo hostnamectl set-hostname worker-1"
$CSSH$W2_PUB "sudo hostnamectl set-hostname worker-2"
$CSSH$W3_PUB "sudo hostnamectl set-hostname worker-3"
$CSSH$W4_PUB "sudo hostnamectl set-hostname worker-4"
echo "  ✓ hostname 설정 완료"

echo "=============================="
echo " Step 4: kubeadm 설치 (전체 노드)"
echo "=============================="
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
$CSSH$M1_PUB "
  sudo kubeadm init \
    --node-name master-1 \
    --pod-network-cidr $POD_CIDR \
    --v=5 2>&1 | tee /tmp/kubeadm-init.log

  mkdir -p \$HOME/.kube
  sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config
  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
"

echo "=============================="
echo " Step 4-2: Worker join 명령어 추출"
echo "=============================="
WORKER_JOIN=$($CSSH$M1_PUB "sudo kubeadm token create --print-join-command")

echo "=============================="
echo " Step 4-3: Worker-1~4 join"
echo "=============================="
$CSSH$W1_PUB "sudo $WORKER_JOIN --node-name worker-1"
echo "  ✓ Worker join: worker-1"
$CSSH$W2_PUB "sudo $WORKER_JOIN --node-name worker-2"
echo "  ✓ Worker join: worker-2"
$CSSH$W3_PUB "sudo $WORKER_JOIN --node-name worker-3"
echo "  ✓ Worker join: worker-3"
$CSSH$W4_PUB "sudo $WORKER_JOIN --node-name worker-4"
echo "  ✓ Worker join: worker-4"

echo "=============================="
echo " Step 4-4: Flannel CNI (VXLAN 모드)"
echo "=============================="
# Calico tigera-operator는 master에 과부하 → Flannel(경량 DaemonSet)으로 교체
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
$CSSH$M1_PUB "
  kubectl label nodes worker-1 worker-2 worker-3 worker-4 role=worker
  kubectl get nodes --show-labels
"

echo "=============================="
echo " Step 4-6: kubeconfig 로컬 저장"
echo "=============================="
mkdir -p ~/.kube
scp $SSH_OPTS ubuntu@$M1_PUB:~/.kube/config ~/.kube/config-k8s-storage-lab
echo ""
echo "✅ Step 4 완료 - kubeconfig → ~/.kube/config-k8s-storage-lab"
echo "   다음: scripts/01_ceph_install.sh"
