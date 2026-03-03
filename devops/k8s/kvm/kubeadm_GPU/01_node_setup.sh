#!/usr/bin/bash
# 01_node_setup.sh
# 모든 노드 공통 설정 (master / worker 동일하게 실행)
# Ubuntu 24.04 | NVIDIA GPU
# ⚠️  실행 후 재부팅 필요

set -e

K8S_VERSION="1.31"

log()        { echo "[$(date '+%H:%M:%S')] $1"; }
error_exit() { echo "❌ ERROR: $1"; exit 1; }

log "=== Phase 1: 노드 공통 설정 시작 ==="

# ────────────────────────────────────────────
# 1. Nouveau 블랙리스트
# ────────────────────────────────────────────
log "1. Nouveau 블랙리스트 설정..."
sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null <<EOF
blacklist nouveau
options nouveau modeset=0
EOF
sudo update-initramfs -u

# ────────────────────────────────────────────
# 2. NVIDIA 드라이버 설치 (동적 감지)
# ────────────────────────────────────────────
log "2. NVIDIA GPU 감지 및 드라이버 설치..."
sudo apt-get update -y
sudo apt-get install -y ubuntu-drivers-common pciutils

NVIDIA_GPU=$(lspci | grep -iE "(VGA|3D|Display).*NVIDIA|NVIDIA.*(VGA|3D|Display)" | head -1)
[[ -z "$NVIDIA_GPU" ]] && error_exit "NVIDIA GPU를 찾을 수 없습니다. lspci 출력을 확인하세요."
log "   감지된 GPU: $NVIDIA_GPU"

RECOMMENDED_DRIVER=$(ubuntu-drivers devices 2>/dev/null \
  | awk '/recommended/ && /nvidia/{print $3}' | head -1)
if [[ -z "$RECOMMENDED_DRIVER" ]]; then
  RECOMMENDED_DRIVER=$(ubuntu-drivers devices 2>/dev/null \
    | awk '/nvidia-driver-[0-9]+/{print $3}' \
    | sort -t- -k3 -V | tail -1)
fi
[[ -z "$RECOMMENDED_DRIVER" ]] && \
  error_exit "적합한 NVIDIA 드라이버를 찾을 수 없습니다. 'ubuntu-drivers devices' 를 확인하세요."
log "   설치할 드라이버: $RECOMMENDED_DRIVER"

sudo apt-get purge -y 'nvidia-*' 2>/dev/null || true
sudo apt-get autoremove -y 2>/dev/null || true
sudo apt-get install -y "$RECOMMENDED_DRIVER"

# PRIME (노트북 iGPU+dGPU 환경에서만 적용, 서버는 자동 스킵)
if apt-cache show nvidia-prime &>/dev/null 2>&1; then
  sudo apt-get install -y nvidia-prime 2>/dev/null || true
  if command -v prime-select &>/dev/null; then
    CPU_VENDOR=$(grep -m1 vendor_id /proc/cpuinfo | awk '{print $3}')
    if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
      sudo prime-select intel 2>/dev/null || true
      log "   PRIME → Intel iGPU (디스플레이), NVIDIA dGPU (compute 전용)"
    else
      sudo prime-select on-demand 2>/dev/null || true
      log "   PRIME → AMD iGPU (디스플레이), NVIDIA dGPU (compute 전용)"
    fi
  fi
fi

# ────────────────────────────────────────────
# 3. nvidia-container-toolkit 설치
# ────────────────────────────────────────────
log "3. nvidia-container-toolkit 설치..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update -y
sudo apt-get install -y nvidia-container-toolkit

# ────────────────────────────────────────────
# 4. 시스템 전제 조건 (swap off, modules, sysctl)
# ────────────────────────────────────────────
log "4. 시스템 설정 (swap off, kernel modules, sysctl)..."

sudo swapoff -a
sudo sed -i '/\bswap\b/s/^[^#]/#&/' /etc/fstab

sudo tee /etc/modules-load.d/k8s.conf > /dev/null <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/k8s.conf > /dev/null <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# ────────────────────────────────────────────
# 5. containerd 설치 + NVIDIA runtime 설정
# ────────────────────────────────────────────
log "5. containerd 설치 및 NVIDIA runtime 설정..."

sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y containerd.io

# containerd 기본 설정 생성
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# SystemdCgroup 활성화 (kubeadm 필수)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# NVIDIA runtime 등록
sudo nvidia-ctk runtime configure --runtime=containerd

sudo systemctl restart containerd
sudo systemctl enable containerd

# ────────────────────────────────────────────
# 6. kubeadm / kubelet / kubectl 설치
# ────────────────────────────────────────────
log "6. kubeadm/kubelet/kubectl v${K8S_VERSION} 설치..."

sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/apt/keyrings

curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet

# ────────────────────────────────────────────
# 완료
# ────────────────────────────────────────────
log "=== Phase 1 완료 ==="
echo ""
echo "✅ 설치 완료:"
echo "   - Nouveau 블랙리스트"
echo "   - NVIDIA 드라이버: $RECOMMENDED_DRIVER ($NVIDIA_GPU)"
echo "   - nvidia-container-toolkit"
echo "   - containerd (NVIDIA runtime 설정)"
echo "   - kubeadm/kubelet/kubectl v${K8S_VERSION}"
echo ""
echo "⚠️  재부팅 후 진행:"
echo "   master 노드 → bash 02_master_init.sh"
echo "   worker 노드 → bash 03_worker_join.sh  (master join 명령 필요)"
echo ""
read -rp "지금 재부팅하시겠습니까? (y/N): " resp
[[ "$resp" =~ ^[yY]$ ]] && sudo init 6 || echo "수동으로 재부팅 후 진행하세요."
