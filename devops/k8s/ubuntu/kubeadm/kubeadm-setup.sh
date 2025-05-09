#!/bin/bash
#=========================================================================
# Kubernetes 클러스터 노드 공통 설정 스크립트
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

# 네트워크 설정 인자 받기
MASTER_IP=$1
NETWORK_PREFIX=$2
WORKER_LENGTH=$3
KUBE_VERSION=$4

# Kubernetes 버전에서 major.minor 추출 (v1.31.0 -> v1.31)
KUBE_MINOR_VERSION=${KUBE_VERSION%.*}

#=========================================================================
# 1. 시스템 기본 설정
#=========================================================================
echo -e "\n[단계 1/6] 시스템 기본 설정을 시작합니다..."

# 방화벽 비활성화
echo ">> 방화벽 비활성화 중..."
sudo ufw disable
sudo systemctl stop ufw
sudo systemctl disable ufw

# Root 설정 및 sudo 권한 부여
echo ">> root 사용자 설정 중..."
echo "root:vagrant" | chpasswd
echo "vagrant ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# root 로그인 활성화
echo ">> SSH 설정 수정 중..."
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
sudo systemctl restart ssh
sudo systemctl restart sshd

#=========================================================================
# 2. 네트워크 설정
#=========================================================================
echo -e "\n[단계 2/6] 네트워크 설정을 시작합니다..."

# /etc/hosts 파일 업데이트
echo ">> /etc/hosts 파일 업데이트 중..."
echo "$MASTER_IP k8s-master" >> /etc/hosts
for ((i=1; i<=WORKER_LENGTH; i++)); do
    echo "${NETWORK_PREFIX}.$((i + 10)) k8s-worker-$i" >> /etc/hosts
done

#=========================================================================
# 3. 컨테이너 런타임 설정
#=========================================================================
echo -e "\n[단계 3/6] 컨테이너 런타임 설정을 시작합니다..."

# 필요한 모듈 로드
echo ">> 커널 모듈 로드 중..."
cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# 필요한 sysctl 설정
echo ">> sysctl 설정 중..."
cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF
sysctl --system

#=========================================================================
# 4. containerd 설치
#=========================================================================
echo -e "\n[단계 4/6] containerd 설치를 시작합니다..."

# APT 업데이트 (단 한 번만 실행)
echo ">> APT 업데이트 중..."
apt-get update

# containerd 설치 및 설정
echo ">> containerd 설치 중..."
apt-get install -y containerd curl apt-transport-https ca-certificates sshpass
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml >/dev/null
sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

#=========================================================================
# 5. Swap 비활성화
#=========================================================================
echo -e "\n[단계 5/6] Swap 비활성화를 시작합니다..."

# swap 비활성화
echo ">> Swap 비활성화 중..."
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab

#=========================================================================
# 6. Kubernetes 컴포넌트 설치
#=========================================================================
echo -e "\n[단계 6/6] Kubernetes 컴포넌트 설치를 시작합니다..."

# Kubernetes GPG 키 추가
echo ">> Kubernetes 저장소 키 추가 중..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBE_MINOR_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBE_MINOR_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

# 새로운 저장소 추가 후 업데이트 필요
echo ">> APT 업데이트 및 Kubernetes 패키지 설치 중..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# APT 캐시 정보 저장 (다른 스크립트에서 참고할 수 있도록)
touch /var/tmp/apt_updated
date "+%Y-%m-%d %H:%M:%S" > /var/tmp/apt_updated

echo -e "\n[완료] Kubernetes 노드 공통 설정이 완료되었습니다."