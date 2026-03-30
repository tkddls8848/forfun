#!/bin/bash
# Phase 2: Frontend — k3s server + agent × 2 설치
# 실행: ssh ubuntu@<FRONTEND_IP> 'sudo bash -s' < 01_k3s_frontend.sh
set -e

K3S_VERSION="v1.31.6+k3s1"
UBUNTU_HOME="/home/ubuntu"
PRIVATE_IP=$(hostname -I | awk '{print $1}')

echo "=============================="
echo " [1/5] 사전 준비"
echo "=============================="
# swap off
swapoff -a
sed -i '/swap/d' /etc/fstab

# 커널 고정
apt-mark hold linux-image-* linux-headers-* 2>/dev/null || true

# 커널 모듈 로드
modprobe overlay
modprobe br_netfilter
cat > /etc/modules-load.d/k3s.conf <<EOF
overlay
br_netfilter
EOF

cat > /etc/sysctl.d/99-k3s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

echo "=============================="
echo " [2/5] k3s server 설치 (${K3S_VERSION})"
echo "=============================="
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  sh -s - server \
  --disable traefik \
  --node-label role=master \
  --node-name k3s-master

# kubeconfig — ubuntu 유저에게도 배포 (sudo 실행 시 HOME=/root이므로 명시)
mkdir -p "${UBUNTU_HOME}/.kube"
cp /etc/rancher/k3s/k3s.yaml "${UBUNTU_HOME}/.kube/config"
sed -i "s/127.0.0.1/${PRIVATE_IP}/g" "${UBUNTU_HOME}/.kube/config"
chown ubuntu:ubuntu "${UBUNTU_HOME}/.kube" "${UBUNTU_HOME}/.kube/config"
chmod 600 "${UBUNTU_HOME}/.kube/config"

export KUBECONFIG="${UBUNTU_HOME}/.kube/config"

echo "=============================="
echo " [3/5] k3s agent-1 설치"
echo "=============================="
K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)

cat > /etc/systemd/system/k3s-agent1.service <<EOF
[Unit]
Description=Lightweight Kubernetes Agent 1
Documentation=https://k3s.io
After=network-online.target

[Service]
Type=exec
EnvironmentFile=/etc/systemd/system/k3s-agent1.env
ExecStart=/usr/local/bin/k3s agent \
  --node-label role=worker \
  --node-name k3s-worker-1 \
  --data-dir /var/lib/rancher/k3s-agent1
KillMode=process
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/k3s-agent1.env <<EOF
K3S_URL=https://${PRIVATE_IP}:6443
K3S_TOKEN=${K3S_TOKEN}
EOF

echo "=============================="
echo " [4/5] k3s agent-2 설치"
echo "=============================="
cat > /etc/systemd/system/k3s-agent2.service <<EOF
[Unit]
Description=Lightweight Kubernetes Agent 2
Documentation=https://k3s.io
After=network-online.target

[Service]
Type=exec
EnvironmentFile=/etc/systemd/system/k3s-agent2.env
ExecStart=/usr/local/bin/k3s agent \
  --node-label role=worker \
  --node-name k3s-worker-2 \
  --data-dir /var/lib/rancher/k3s-agent2
KillMode=process
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/k3s-agent2.env <<EOF
K3S_URL=https://${PRIVATE_IP}:6443
K3S_TOKEN=${K3S_TOKEN}
EOF

systemctl daemon-reload
systemctl enable --now k3s-agent1
systemctl enable --now k3s-agent2

echo "=============================="
echo " [5/5] 노드 확인 (30초 대기)"
echo "=============================="
sleep 30
kubectl get nodes
echo ""
echo "✅ k3s frontend 구성 완료"
echo "   kubeconfig: ${UBUNTU_HOME}/.kube/config"
