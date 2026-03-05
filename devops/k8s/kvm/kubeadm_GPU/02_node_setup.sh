#!/usr/bin/bash
# 02_node_setup.sh
# 모든 노드 공통 설정 (master / worker 동일하게 실행)
# Ubuntu 24.04 | NVIDIA GPU
# ⚠️  실행 후 재부팅 필요
#
# GPU_MODE 환경변수로 GPU 설치 방식 선택:
#   GPU_MODE=full        (기본값) 베어메탈 전용 NVIDIA 드라이버 + toolkit 전체 설치
#   GPU_MODE=toolkit-vm  KVM VM용: /dev/nvidia* 장치는 호스트에서 제공, userspace + toolkit만 설치
#   GPU_MODE=none        GPU 없는 노드 (master 등): NVIDIA 관련 설치 전체 스킵
#
# 예시:
#   GPU_MODE=none       bash 02_node_setup.sh   # master
#   GPU_MODE=toolkit-vm bash 02_node_setup.sh   # KVM worker (VM)
#   bash 02_node_setup.sh                        # 베어메탈 worker

set -e

K8S_VERSION="1.31"
GPU_MODE="${GPU_MODE:-full}"

log()        { echo "[$(date '+%H:%M:%S')] $1"; }
error_exit() { echo "❌ ERROR: $1"; exit 1; }

log "=== Phase 2: 노드 공통 설정 시작 (GPU_MODE=$GPU_MODE) ==="

# CPU 제조사 감지 (PRIME 설정에 사용)
CPU_VENDOR=$(grep -m1 vendor_id /proc/cpuinfo | awk '{print $3}')
log "   CPU: $CPU_VENDOR"

# ────────────────────────────────────────────
# 1. Nouveau 블랙리스트 (GPU 있는 노드만)
# ────────────────────────────────────────────
if [[ "$GPU_MODE" != "none" ]]; then
  log "1. Nouveau 블랙리스트 설정..."
  sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null <<EOF
blacklist nouveau
options nouveau modeset=0
EOF
  sudo update-initramfs -u
else
  log "1. Nouveau 블랙리스트 → 스킵 (GPU_MODE=none)"
fi

# ────────────────────────────────────────────
# 2. NVIDIA 드라이버 설치 (GPU_MODE에 따라 분기)
# ────────────────────────────────────────────
sudo apt-get update -y

if [[ "$GPU_MODE" == "full" ]]; then
  # 베어메탈: 커널 드라이버 + userspace 전체 설치
  log "2. [full] NVIDIA GPU 감지 및 드라이버 설치..."
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
      if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
        sudo prime-select intel 2>/dev/null || true
        log "   PRIME → Intel iGPU (디스플레이), NVIDIA dGPU (compute 전용)"
      else
        sudo prime-select on-demand 2>/dev/null || true
        log "   PRIME → AMD iGPU (디스플레이), NVIDIA dGPU (compute 전용)"
      fi
    fi
  fi

elif [[ "$GPU_MODE" == "toolkit-vm" ]]; then
  # KVM VM: 커널 모듈 없이 userspace 라이브러리만 설치
  # /dev/nvidia* 장치는 호스트에서 libvirt가 제공
  log "2. [toolkit-vm] NVIDIA userspace 라이브러리만 설치 (커널 모듈 제외)..."

  # 호스트 드라이버 버전 파일이 있으면 일치시킴
  if [[ -f /tmp/host_driver_major ]]; then
    DRIVER_MAJOR=$(cat /tmp/host_driver_major)
  else
    # 자동 감지 불가 시 최신 버전 사용
    DRIVER_MAJOR=$(apt-cache search 'nvidia-utils-[0-9]+' \
      | awk '{print $1}' | grep -oE '[0-9]+' | sort -V | tail -1)
  fi
  log "   nvidia-utils-${DRIVER_MAJOR} 설치 중..."
  sudo apt-get install -y "nvidia-utils-${DRIVER_MAJOR}" 2>/dev/null || \
    sudo apt-get install -y nvidia-utils 2>/dev/null || true

  # NVIDIA 커널 모듈 블랙리스트 (VM에서 로드 방지)
  sudo tee /etc/modprobe.d/blacklist-nvidia-km.conf > /dev/null <<'EOF'
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_uvm
blacklist nvidia_modeset
EOF
  sudo update-initramfs -u
  log "   NVIDIA 커널 모듈 블랙리스트 설정 완료"

else
  log "2. NVIDIA 드라이버 설치 → 스킵 (GPU_MODE=none)"
fi

# ────────────────────────────────────────────
# 3. nvidia-container-toolkit 설치 (GPU 노드만)
# ────────────────────────────────────────────
if [[ "$GPU_MODE" != "none" ]]; then
  log "3. nvidia-container-toolkit 설치..."
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

  sudo apt-get update -y
  sudo apt-get install -y nvidia-container-toolkit
else
  log "3. nvidia-container-toolkit → 스킵 (GPU_MODE=none)"
fi

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

# NVIDIA runtime 등록 (GPU 노드만)
if [[ "$GPU_MODE" != "none" ]]; then
  sudo nvidia-ctk runtime configure --runtime=containerd
fi

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
sudo apt-get install -y kubelet kubeadm kubectl conntrack
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet

# ────────────────────────────────────────────
# 완료
# ────────────────────────────────────────────
log "=== Phase 1 완료 ==="
echo ""
echo "✅ 설치 완료 (GPU_MODE=$GPU_MODE):"
case "$GPU_MODE" in
  full)
    echo "   - Nouveau 블랙리스트"
    echo "   - NVIDIA 드라이버 (베어메탈 전체 설치)"
    echo "   - nvidia-container-toolkit"
    ;;
  toolkit-vm)
    echo "   - Nouveau 블랙리스트"
    echo "   - NVIDIA userspace 라이브러리만 (커널 모듈 제외)"
    echo "   - NVIDIA 커널 모듈 블랙리스트"
    echo "   - nvidia-container-toolkit"
    ;;
  none)
    echo "   - NVIDIA 관련 설치 없음 (master 노드)"
    ;;
esac
echo "   - containerd (NVIDIA runtime 설정)"
echo "   - kubeadm/kubelet/kubectl v${K8S_VERSION}"
echo ""
echo "⚠️  재부팅 후 진행:"
echo "   master 노드 → bash 03_master_init.sh"
echo "   worker 노드 → bash 04_worker_join.sh  (master join 명령 필요)"
echo ""
read -rp "지금 재부팅하시겠습니까? (y/N): " resp
[[ "$resp" =~ ^[yY]$ ]] && sudo init 6 || echo "수동으로 재부팅 후 진행하세요."
