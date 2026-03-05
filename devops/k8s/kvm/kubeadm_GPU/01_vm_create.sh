#!/usr/bin/bash
# 01_vm_create.sh
# K8s용 KVM VM 3개 생성 (master 1, worker 2)
# Worker VM에 /dev/nvidia* 장치 자동 연결 (toolkit 공유 방식)
#
# 리소스 (CUDA 최소 사양 1.2배):
#   Master : 2 vCPU, 4096MB RAM, 30GB disk
#   Worker : 3 vCPU, 5120MB RAM, 50GB disk
#
# 실행: bash 01_vm_create.sh
# 완료 후 각 VM에서 02_node_setup.sh 실행

set -e

log()        { echo "[$(date '+%H:%M:%S')] $1"; }
warn()       { echo "[$(date '+%H:%M:%S')] WARNING: $1"; }
error_exit() { echo "❌ ERROR: $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log "=== VM 생성 시작 ==="

# ────────────────────────────────────────────
# 설정값
# ────────────────────────────────────────────
VM_DIR="/var/lib/libvirt/images"
SETUP_DIR="/var/lib/libvirt/images/k8s-setup"
CLOUD_IMG="$SETUP_DIR/ubuntu-24.04-cloud.img"
CLOUD_IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

# VM 리소스 (CUDA 최소 1.2배)
MASTER_VCPU=2;  MASTER_MEM=4096;  MASTER_DISK=30   # master
WORKER_VCPU=3;  WORKER_MEM=5120;  WORKER_DISK=50   # worker (1.2x CUDA min)

# VM 이름 / IP (libvirt default NAT: 192.168.122.x)
MASTER_NAME="k8s-master"
WORKER1_NAME="k8s-worker1"
WORKER2_NAME="k8s-worker2"

SSH_KEY_PATH="$HOME/.ssh/id_ed25519.pub"

sudo mkdir -p "$SETUP_DIR"
sudo chown "$(id -u):$(id -g)" "$SETUP_DIR"

# ────────────────────────────────────────────
# 0. 사전 확인
# ────────────────────────────────────────────
log "0. 사전 확인..."

[[ -f "/var/lib/libvirt/images/k8s-setup/host_info.env" ]] \
  && source "/var/lib/libvirt/images/k8s-setup/host_info.env" \
  || error_exit "host_info.env 없음. 먼저 00_host_setup.sh를 실행하세요."

log "   CPU: $CPU_VENDOR | GPU: $GPU_NAME | 드라이버: $DRIVER_VERSION"

# SSH 키 확인 (없으면 생성)
if [[ ! -f "$SSH_KEY_PATH" ]]; then
  log "   SSH 키 생성 중..."
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N ""
fi
SSH_PUB_KEY=$(cat "$SSH_KEY_PATH")

# /dev/nvidia* 장치 목록 수집
NVIDIA_DEVS=()
for dev in /dev/nvidia0 /dev/nvidiactl /dev/nvidia-uvm /dev/nvidia-uvm-tools; do
  [[ -e "$dev" ]] && NVIDIA_DEVS+=("$dev")
done
[[ ${#NVIDIA_DEVS[@]} -eq 0 ]] && error_exit "/dev/nvidia* 장치를 찾을 수 없습니다."
log "   연결할 GPU 장치: ${NVIDIA_DEVS[*]}"

# ────────────────────────────────────────────
# 1. Ubuntu 24.04 클라우드 이미지 다운로드
# ────────────────────────────────────────────
log "1. Ubuntu 24.04 클라우드 이미지 확인 중..."

if [[ -f "$CLOUD_IMG" ]]; then
  log "   이미지 이미 존재: $CLOUD_IMG (재사용)"
else
  log "   다운로드 중: $CLOUD_IMG_URL"
  wget -O "$CLOUD_IMG" "$CLOUD_IMG_URL"
  log "   다운로드 완료"
fi

# ────────────────────────────────────────────
# 2. cloud-init 설정 생성 함수
# ────────────────────────────────────────────
create_cloud_init() {
  local vm_name="$1"
  local gpu_mode="$2"   # none | toolkit-vm

  local seed_dir="$SETUP_DIR/cloud-init-$vm_name"
  mkdir -p "$seed_dir"

  # VM 역할에 맞는 스크립트를 base64로 인코딩 (write_files 삽입용)
  local write_files_section=""
  local b64_02 b64_03 b64_04
  b64_02=$(base64 -w0 "$SCRIPT_DIR/02_node_setup.sh" 2>/dev/null || true)
  b64_03=$(base64 -w0 "$SCRIPT_DIR/03_master_init.sh" 2>/dev/null || true)
  b64_04=$(base64 -w0 "$SCRIPT_DIR/04_worker_join.sh" 2>/dev/null || true)

  if [[ -n "$b64_02" ]]; then
    write_files_section+="
  - path: /home/ubuntu/02_node_setup.sh
    permissions: '0755'
    owner: ubuntu:ubuntu
    encoding: b64
    content: $b64_02"
  fi

  if [[ "$vm_name" == *"master"* && -n "$b64_03" ]]; then
    write_files_section+="
  - path: /home/ubuntu/03_master_init.sh
    permissions: '0755'
    owner: ubuntu:ubuntu
    encoding: b64
    content: $b64_03"
  fi

  if [[ "$vm_name" != *"master"* && -n "$b64_04" ]]; then
    write_files_section+="
  - path: /home/ubuntu/04_worker_join.sh
    permissions: '0755'
    owner: ubuntu:ubuntu
    encoding: b64
    content: $b64_04"
  fi

  # NVIDIA 관련 패키지 (toolkit-vm 모드)
  local nvidia_packages=""
  local nvidia_postinstall=""

  if [[ "$gpu_mode" == "toolkit-vm" ]]; then
    nvidia_packages="
    - nvidia-utils-${DRIVER_MAJOR}
    - nvidia-container-toolkit"
    nvidia_postinstall="
  - |
    # NVIDIA 커널 모듈 블랙리스트 (장치는 호스트에서 제공)
    echo 'blacklist nvidia' > /etc/modprobe.d/blacklist-nvidia-km.conf
    echo 'blacklist nvidia_drm' >> /etc/modprobe.d/blacklist-nvidia-km.conf
    echo 'blacklist nvidia_uvm' >> /etc/modprobe.d/blacklist-nvidia-km.conf
    echo 'blacklist nvidia_modeset' >> /etc/modprobe.d/blacklist-nvidia-km.conf
    update-initramfs -u"
  fi

  # user-data
  cat > "$seed_dir/user-data" <<USERDATA
#cloud-config
hostname: ${vm_name}
manage_etc_hosts: true

users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    home: /home/ubuntu
    create_home: true
    ssh_authorized_keys:
      - ${SSH_PUB_KEY}

chpasswd:
  list: |
    ubuntu:ubuntu
  expire: false

ssh_pwauth: true

apt:
  sources:
    nvidia-container-toolkit:
      source: "deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH) /"
      key: |
$(curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey 2>/dev/null | sed 's/^/        /' || echo "        # GPG key fetch failed")

packages:${nvidia_packages}
  - curl
  - apt-transport-https
  - ca-certificates
  - gpg

write_files:${write_files_section}

runcmd:
  - chown ubuntu:ubuntu /home/ubuntu
  - swapoff -a
  - sed -i '/\bswap\b/s/^[^#]/#&/' /etc/fstab${nvidia_postinstall}

final_message: "VM $vm_name cloud-init 완료"
USERDATA

  # meta-data
  cat > "$seed_dir/meta-data" <<METADATA
instance-id: ${vm_name}
local-hostname: ${vm_name}
METADATA

  # seed ISO 생성
  cloud-localds "$SETUP_DIR/${vm_name}-seed.iso" \
    "$seed_dir/user-data" "$seed_dir/meta-data"
  log "   cloud-init seed: $SETUP_DIR/${vm_name}-seed.iso"
}

# ────────────────────────────────────────────
# 3. VM 디스크 생성 함수
# ────────────────────────────────────────────
create_vm_disk() {
  local vm_name="$1"
  local size_gb="$2"
  local dst="$VM_DIR/${vm_name}.qcow2"

  if [[ -f "$dst" ]]; then
    # backing file 경로가 현재 CLOUD_IMG와 일치하는지 확인
    local backing
    backing=$(sudo qemu-img info "$dst" 2>/dev/null | awk '/backing file:/{print $3}')
    if [[ "$backing" != "$CLOUD_IMG" ]]; then
      log "   backing file 불일치 ($backing) → 디스크 재생성"
      sudo rm -f "$dst"
    else
      log "   디스크 이미 존재: $dst (스킵)"
      return 0
    fi
  fi
  if true; then
    sudo qemu-img create -f qcow2 -b "$CLOUD_IMG" -F qcow2 "$dst" "${size_gb}G"
    sudo chmod 644 "$dst"
    log "   디스크 생성: $dst (${size_gb}GB)"
  fi
}

# ────────────────────────────────────────────
# 4. VM 생성 함수
# ────────────────────────────────────────────
create_vm() {
  local vm_name="$1"
  local vcpu="$2"
  local mem="$3"
  local disk_gb="$4"
  local gpu_mode="$5"   # none | toolkit-vm

  log "--- VM 생성: $vm_name (${vcpu}vCPU / ${mem}MB / ${disk_gb}GB / GPU: $gpu_mode) ---"

  # 이미 존재하면 스킵
  if sudo virsh dominfo "$vm_name" &>/dev/null; then
    log "   VM '$vm_name' 이미 존재. 스킵"
    return 0
  fi

  create_vm_disk "$vm_name" "$disk_gb"
  create_cloud_init "$vm_name" "$gpu_mode"

  # CPU 제조사에 따른 최적화 옵션
  local cpu_model
  case "$CPU_VENDOR" in
    GenuineIntel) cpu_model="host-model" ;;
    AuthenticAMD) cpu_model="host-passthrough" ;;
    *)            cpu_model="host-model" ;;
  esac

  sudo virt-install \
    --name "$vm_name" \
    --vcpus "$vcpu" \
    --memory "$mem" \
    --disk "path=$VM_DIR/${vm_name}.qcow2,format=qcow2,bus=virtio" \
    --disk "path=$SETUP_DIR/${vm_name}-seed.iso,device=cdrom" \
    --os-variant "ubuntu24.04" \
    --network network=default,model=virtio \
    --cpu "$cpu_model" \
    --graphics none \
    --console "pty,target_type=serial" \
    --import \
    --noautoconsole

  log "   VM '$vm_name' 생성 완료"

  # GPU worker에 /dev/nvidia* 장치 연결
  if [[ "$gpu_mode" == "toolkit-vm" ]]; then
    log "   GPU 장치 연결 중..."
    for dev in "${NVIDIA_DEVS[@]}"; do
      local major minor type
      major=$(stat -c '%t' "$dev" | tr '[:lower:]' '[:upper:]')
      minor=$(stat -c '%T' "$dev" | tr '[:lower:]' '[:upper:]')
      type=$(stat -c '%F' "$dev")

      # char device 인 경우만 추가
      if [[ "$type" == "character special file" ]]; then
        local tmp_xml
        tmp_xml=$(mktemp /tmp/hostdev-XXXXXX.xml)
        cat > "$tmp_xml" <<XMLEOF
<hostdev mode='capabilities' type='char'>
  <source>
    <char>${dev}</char>
  </source>
</hostdev>
XMLEOF
        sudo virsh attach-device "$vm_name" --persistent "$tmp_xml" 2>/dev/null || true
        rm -f "$tmp_xml"
        log "   장치 연결: $dev"
      fi
    done
  fi
}

# ────────────────────────────────────────────
# 5. VM 3개 생성
# ────────────────────────────────────────────
log "5. VM 생성 중..."

create_vm "$MASTER_NAME"  "$MASTER_VCPU" "$MASTER_MEM"  "$MASTER_DISK"  "none"
create_vm "$WORKER1_NAME" "$WORKER_VCPU" "$WORKER_MEM"  "$WORKER_DISK"  "toolkit-vm"
create_vm "$WORKER2_NAME" "$WORKER_VCPU" "$WORKER_MEM"  "$WORKER_DISK"  "toolkit-vm"

# ────────────────────────────────────────────
# 6. VM IP 확인 대기
# ────────────────────────────────────────────
log "6. VM 부팅 대기 중 (최대 3분)..."
sleep 30

declare -A VM_IPS
for vm_name in "$MASTER_NAME" "$WORKER1_NAME" "$WORKER2_NAME"; do
  log "   $vm_name IP 확인 중..."
  for i in $(seq 1 18); do
    IP=$(sudo virsh domifaddr "$vm_name" 2>/dev/null \
      | grep -oE '192\.168\.[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$IP" ]]; then
      VM_IPS[$vm_name]="$IP"
      log "   $vm_name → $IP"
      break
    fi
    sleep 10
  done
  [[ -z "${VM_IPS[$vm_name]}" ]] && warn "$vm_name IP 확인 실패 (수동 확인: sudo virsh domifaddr $vm_name)"
done

# VM IP 저장
cat > "$SETUP_DIR/vm_ips.env" <<EOF
MASTER_IP=${VM_IPS[$MASTER_NAME]:-unknown}
WORKER1_IP=${VM_IPS[$WORKER1_NAME]:-unknown}
WORKER2_IP=${VM_IPS[$WORKER2_NAME]:-unknown}
MASTER_NAME=$MASTER_NAME
WORKER1_NAME=$WORKER1_NAME
WORKER2_NAME=$WORKER2_NAME
EOF
log "VM IP 저장: $SETUP_DIR/vm_ips.env"

# ────────────────────────────────────────────
# 완료
# ────────────────────────────────────────────
log "=== VM 생성 완료 ==="
echo ""
echo "VM 구성:"
printf "  %-15s %s vCPU / %sMB RAM / %sGB disk | GPU: none\n" \
  "$MASTER_NAME" "$MASTER_VCPU" "$MASTER_MEM" "$MASTER_DISK"
printf "  %-15s %s vCPU / %sMB RAM / %sGB disk | GPU: toolkit (shared)\n" \
  "$WORKER1_NAME" "$WORKER_VCPU" "$WORKER_MEM" "$WORKER_DISK"
printf "  %-15s %s vCPU / %sMB RAM / %sGB disk | GPU: toolkit (shared)\n" \
  "$WORKER2_NAME" "$WORKER_VCPU" "$WORKER_MEM" "$WORKER_DISK"
echo ""
echo "VM IP 확인:"
for vm_name in "$MASTER_NAME" "$WORKER1_NAME" "$WORKER2_NAME"; do
  echo "  sudo virsh domifaddr $vm_name"
done
echo ""
echo "SSH 접속:"
echo "  ssh ubuntu@${VM_IPS[$MASTER_NAME]:-<master-ip>}"
echo ""
echo "다음 단계 (각 VM에 SSH 접속 후):"
echo ""
echo "  [Master]"
echo "  scp 02_node_setup.sh 03_master_init.sh ubuntu@${VM_IPS[$MASTER_NAME]:-<master-ip>}:~/"
echo "  ssh ubuntu@${VM_IPS[$MASTER_NAME]:-<master-ip>} 'GPU_MODE=none bash 02_node_setup.sh'"
echo ""
echo "  [Worker1, Worker2]"
echo "  scp 02_node_setup.sh 04_worker_join.sh ubuntu@${VM_IPS[$WORKER1_NAME]:-<worker1-ip>}:~/"
echo "  ssh ubuntu@${VM_IPS[$WORKER1_NAME]:-<worker1-ip>} 'GPU_MODE=toolkit-vm bash 02_node_setup.sh'"
