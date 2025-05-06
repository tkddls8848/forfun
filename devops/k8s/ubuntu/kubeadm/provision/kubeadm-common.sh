#!/bin/bash

set -e

# 네트워크 설정 인자 받기
MASTER_IP=$1
NETWORK_PREFIX=$2
WORKER_LENGTH=$3

# 방화벽 비활성화
sudo ufw disable
sudo systemctl stop ufw
sudo systemctl disable ufw

# Root 설정 및 sudo 권한 부여
echo "root:vagrant" | chpasswd
echo "vagrant ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# root 로그인 활성화
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
sudo systemctl restart ssh
sudo systemctl restart sshd

# /etc/hosts 파일 업데이트
echo "$MASTER_IP k8s-master" >> /etc/hosts
for ((i=1; i<=WORKER_LENGTH; i++)); do
    echo "${NETWORK_PREFIX}.$((i + 10)) k8s-worker-$i" >> /etc/hosts
done

# 필요한 모듈 로드
cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# 필요한 sysctl 설정
cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF
sysctl --system

# containerd 설치 및 설정
apt-get update
apt-get install -y containerd curl apt-transport-https ca-certificates sshpass
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml >/dev/null
sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# swap 비활성화
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab

# Kubernetes 컴포넌트 설치
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# python 설치 및 설정
apt-get update
apt-get install -y python3