#!/bin/bash
set -e
source scripts/.env

SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

K8S_VERSION="1.29"
POD_CIDR="192.168.0.0/16"
CONTROL_PLANE_EP="$M1_PRIV:6443"

ALL_K8S_PUB=($M1_PUB $M2_PUB $M3_PUB $W1_PUB $W2_PUB $W3_PUB)

echo "=============================="
echo " Step 4: kubeadm 설치"
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
    --control-plane-endpoint '$CONTROL_PLANE_EP' \
    --pod-network-cidr $POD_CIDR \
    --upload-certs \
    --v=5 2>&1 | tee /tmp/kubeadm-init.log

  mkdir -p \$HOME/.kube
  sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config
  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
"

echo "=============================="
echo " Step 4-2: join 명령어 추출"
echo "=============================="
MASTER_JOIN=$($CSSH$M1_PUB "sudo kubeadm token create --print-join-command --certificate-key \$(sudo kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)")
WORKER_JOIN=$($CSSH$M1_PUB "sudo kubeadm token create --print-join-command")

echo "=============================="
echo " Step 4-3: Master-2, Master-3 join"
echo "=============================="
for ip in $M2_PUB $M3_PUB; do
  $CSSH$ip "sudo $MASTER_JOIN --control-plane"
  $CSSH$ip "
    mkdir -p \$HOME/.kube
    sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config
    sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
  "
  echo "  ✓ Master join: $ip"
done

echo "=============================="
echo " Step 4-4: Worker join"
echo "=============================="
for ip in $W1_PUB $W2_PUB $W3_PUB; do
  $CSSH$ip "sudo $WORKER_JOIN"
  echo "  ✓ Worker join: $ip"
done

echo "=============================="
echo " Step 4-5: Calico CNI"
echo "=============================="
$CSSH$M1_PUB "
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

  kubectl wait --for=condition=Ready nodes --all --timeout=300s
  kubectl get nodes -o wide
"

echo "=============================="
echo " Step 4-6: NSD taint"
echo "=============================="
$CSSH$M1_PUB "
  kubectl taint nodes nsd-1 dedicated=gpfs-nsd:NoSchedule || true
  kubectl taint nodes nsd-2 dedicated=gpfs-nsd:NoSchedule || true
  kubectl label nodes nsd-1 role=nsd
  kubectl label nodes nsd-2 role=nsd
  kubectl get nodes
"

scp $SSH_OPTS ubuntu@$M1_PUB:~/.kube/config ~/.kube/config-k8s-storage-lab
echo ""
echo "✅ Step 4 완료 - kubeconfig → ~/.kube/config-k8s-storage-lab"
echo "   다음: scripts/05_csi_ceph.sh"
