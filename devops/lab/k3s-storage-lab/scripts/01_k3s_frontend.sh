#!/bin/bash
# Phase 2: Frontend — k3s server 서비스 등록 + agent × 2 조인
# 전제: k3s 바이너리는 Packer AMI에 사전 설치됨 (INSTALL_K3S_SKIP_DOWNLOAD=true)
# 실행: ssh ubuntu@<FRONTEND_IP> 'sudo bash -s' < 01_k3s_frontend.sh
set -e

K3S_VERSION="v1.31.6+k3s1"
UBUNTU_HOME="/home/ubuntu"
PRIVATE_IP=$(hostname -I | awk '{print $1}')
# BeeGFS 7.4.6 클라이언트 모듈 호환 커널 버전 (6.9 이상 미지원)
REQUIRED_KERNEL="6.8"

echo "=============================="
echo " [1/4] k3s server 서비스 등록 (${K3S_VERSION})"
echo "=============================="
# 커널 버전 확인 — BeeGFS 클라이언트 호환성 보장
KERNEL_MAJOR=$(uname -r | cut -d. -f1)
KERNEL_MINOR=$(uname -r | cut -d. -f2)
if [ "$KERNEL_MAJOR" -gt 6 ] || { [ "$KERNEL_MAJOR" -eq 6 ] && [ "$KERNEL_MINOR" -gt 8 ]; }; then
  echo "❌ 현재 커널 $(uname -r) 은 BeeGFS ${REQUIRED_KERNEL} 지원 범위를 벗어납니다."
  echo "   Packer AMI 를 6.8 커널로 다시 빌드 후 재배포하세요 (scripts/00_build_ami.sh)."
  exit 1
fi
echo "  커널 버전 확인: $(uname -r) ✅"
apt-mark hold linux-image-* linux-headers-* 2>/dev/null || true
# INSTALL_K3S_SKIP_DOWNLOAD=true: 바이너리 재다운로드 없이 서비스만 등록
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  INSTALL_K3S_SKIP_DOWNLOAD=true \
  sh -s - server \
  --disable traefik \
  --node-label role=master \
  --node-name k3s-master

mkdir -p "${UBUNTU_HOME}/.kube"
cp /etc/rancher/k3s/k3s.yaml "${UBUNTU_HOME}/.kube/config"
sed -i "s/127.0.0.1/${PRIVATE_IP}/g" "${UBUNTU_HOME}/.kube/config"
chown ubuntu:ubuntu "${UBUNTU_HOME}/.kube" "${UBUNTU_HOME}/.kube/config"
chmod 600 "${UBUNTU_HOME}/.kube/config"

# ubuntu 유저 로그인 시 자동으로 kubeconfig 적용
grep -q "KUBECONFIG" "${UBUNTU_HOME}/.bashrc" || \
  echo "export KUBECONFIG=${UBUNTU_HOME}/.kube/config" >> "${UBUNTU_HOME}/.bashrc"

export KUBECONFIG="${UBUNTU_HOME}/.kube/config"

echo "=============================="
echo " [2/4] k3s agent-1 서비스 등록"
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
echo " [3/4] k3s agent-2 서비스 등록"
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
echo " [4/4] 노드 확인 (30초 대기)"
echo "=============================="
sleep 30
kubectl get nodes
echo ""
echo "k3s frontend 구성 완료 (Packer AMI)"
echo "   kubeconfig: ${UBUNTU_HOME}/.kube/config"
