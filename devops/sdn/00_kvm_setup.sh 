#!/bin/bash
# =============================================================
# 00_kvm_setup.sh
# 역할: KVM/QEMU 설치 + SDN 실습용 VM 3개 생성
#   vm-controller  4vCPU / 8GB  ← ODL + K8s control-plane
#   vm-worker1     2vCPU / 4GB  ← K8s worker + Mininet
#   vm-worker2     2vCPU / 4GB  ← K8s worker + OVS
# 실행: sudo bash 00_kvm_setup.sh
# =============================================================
set -euo pipefail

### ── 변수 ──────────────────────────────────────────────────
IMG_DIR="/var/lib/libvirt/images"
ISO_URL="https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
ISO_PATH="${IMG_DIR}/ubuntu-22.04-server.iso"
BRIDGE_NAME="virbr-sdn"
BRIDGE_IP="192.168.100.1"
BRIDGE_CIDR="192.168.100.0/24"

declare -A VM_VCPU=( [vm-controller]=4 [vm-worker1]=2 [vm-worker2]=2 )
declare -A VM_RAM=(  [vm-controller]=8192 [vm-worker1]=4096 [vm-worker2]=4096 )
declare -A VM_DISK=( [vm-controller]=40 [vm-worker1]=30 [vm-worker2]=30 )
declare -A VM_IP=(   [vm-controller]="192.168.100.10" [vm-worker1]="192.168.100.11" [vm-worker2]="192.168.100.12" )

### ── 1. KVM 패키지 설치 ─────────────────────────────────────
echo "[1/5] KVM 패키지 설치 중..."
apt update -qq
apt install -y \
  qemu-kvm libvirt-daemon-system libvirt-clients virtinst \
  bridge-utils virt-manager cloud-image-utils genisoimage \
  cpu-checker

# KVM 사용 가능 여부 확인
if ! kvm-ok &>/dev/null; then
  echo "❌  KVM 하드웨어 가속을 지원하지 않습니다."
  echo "    BIOS에서 VT-x/AMD-V 활성화 후 재실행하세요."
  exit 1
fi

systemctl enable --now libvirtd
usermod -aG libvirt,kvm "$SUDO_USER"
echo "✅  KVM 설치 완료"

### ── 2. 전용 브리지 네트워크 생성 ──────────────────────────
echo "[2/5] SDN 전용 브리지 네트워크 구성 중..."

cat > /tmp/sdn-network.xml <<EOF
<network>
  <name>sdn-net</name>
  <forward mode='nat'/>
  <bridge name='${BRIDGE_NAME}' stp='on' delay='0'/>
  <ip address='${BRIDGE_IP}' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.100.100' end='192.168.100.199'/>
      <host mac='52:54:00:00:01:10' name='vm-controller' ip='${VM_IP[vm-controller]}'/>
      <host mac='52:54:00:00:01:11' name='vm-worker1'    ip='${VM_IP[vm-worker1]}'/>
      <host mac='52:54:00:00:01:12' name='vm-worker2'    ip='${VM_IP[vm-worker2]}'/>
    </dhcp>
  </ip>
</network>
EOF

virsh net-destroy  sdn-net 2>/dev/null || true
virsh net-undefine sdn-net 2>/dev/null || true
virsh net-define  /tmp/sdn-network.xml
virsh net-start   sdn-net
virsh net-autostart sdn-net
echo "✅  브리지 네트워크 생성 완료 (${BRIDGE_CIDR})"

### ── 3. Ubuntu 22.04 ISO 다운로드 ──────────────────────────
echo "[3/5] Ubuntu 22.04 Server ISO 다운로드..."
if [[ ! -f "${ISO_PATH}" ]]; then
  wget -q --show-progress -O "${ISO_PATH}" "${ISO_URL}"
else
  echo "    ↳ ISO 캐시 사용: ${ISO_PATH}"
fi

### ── 4. cloud-init preseed 이미지 생성 함수 ────────────────
make_cloudinit() {
  local vmname=$1
  local vmip=$2
  local seed_dir="/tmp/cloudinit-${vmname}"
  mkdir -p "${seed_dir}"

  cat > "${seed_dir}/user-data" <<YAML
#cloud-config
hostname: ${vmname}
manage_etc_hosts: true
users:
  - name: sdn
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    passwd: \$6\$rounds=4096\$saltsalt\$yGFNtbbw9W3rSmIFQTocoFqzP0mcDmGiZPXILt93Hv3n2XGH7j8qpHWgLalFbqBaJBbP3UgITYHyb3FhQ1rK11
    # 기본 비밀번호: sdn1234
ssh_pwauth: true
package_update: true
packages:
  - openssh-server
  - net-tools
  - curl
  - wget
  - git
  - vim
  - htop
runcmd:
  - systemctl enable ssh
  - systemctl start ssh
YAML

  cat > "${seed_dir}/meta-data" <<YAML
instance-id: ${vmname}
local-hostname: ${vmname}
YAML

  local seed_img="${IMG_DIR}/seed-${vmname}.iso"
  genisoimage -output "${seed_img}" \
    -volid cidata -joliet -rock \
    "${seed_dir}/user-data" \
    "${seed_dir}/meta-data" 2>/dev/null
  echo "${seed_img}"
}

### ── 5. VM 생성 ─────────────────────────────────────────────
echo "[4/5] VM 디스크 + cloud-init 이미지 생성 중..."
MAC_SUFFIX=10
for VM in vm-controller vm-worker1 vm-worker2; do
  DISK_IMG="${IMG_DIR}/${VM}.qcow2"
  SEED_IMG=$(make_cloudinit "${VM}" "${VM_IP[$VM]}")
  MAC="52:54:00:00:01:${MAC_SUFFIX}"

  # 기존 VM 제거
  virsh destroy  "${VM}" 2>/dev/null || true
  virsh undefine "${VM}" --remove-all-storage 2>/dev/null || true

  # 디스크 생성
  qemu-img create -f qcow2 "${DISK_IMG}" "${VM_DISK[$VM]}G" -q

  echo "    ▶ ${VM} 생성 중 (vCPU:${VM_VCPU[$VM]} RAM:${VM_RAM[$VM]}MB MAC:${MAC})..."
  virt-install \
    --name        "${VM}" \
    --vcpus       "${VM_VCPU[$VM]}" \
    --memory      "${VM_RAM[$VM]}" \
    --disk        "path=${DISK_IMG},format=qcow2,bus=virtio" \
    --disk        "path=${SEED_IMG},device=cdrom" \
    --cdrom       "${ISO_PATH}" \
    --network     "network=sdn-net,mac=${MAC},model=virtio" \
    --os-variant  ubuntu22.04 \
    --graphics    none \
    --console     pty,target_type=serial \
    --extra-args  'console=ttyS0,115200n8 autoinstall' \
    --noautoconsole \
    --wait        0

  MAC_SUFFIX=$((MAC_SUFFIX + 1))
  echo "    ✅  ${VM} 생성 완료 → IP: ${VM_IP[$VM]}"
done

### ── 완료 안내 ──────────────────────────────────────────────
echo ""
echo "[5/5] ✅  모든 VM 생성 완료!"
echo "========================================"
echo "  VM 목록:"
virsh list --all
echo ""
echo "  접속 방법 (초기 비밀번호: sdn1234):"
for VM in vm-controller vm-worker1 vm-worker2; do
  echo "    ssh sdn@${VM_IP[$VM]}"
done
echo ""
echo "  다음 단계: 각 VM에서 01_mininet.sh 실행"
echo "  ※ VM 부팅 완료까지 약 2~5분 소요됩니다."
echo "========================================"