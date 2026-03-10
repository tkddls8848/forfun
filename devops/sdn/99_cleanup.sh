#!/bin/bash
# =============================================================
# 99_cleanup.sh
# 역할: 전체 SDN 실습 환경 정리
# 실행: sudo bash 99_cleanup.sh
# =============================================================
set -euo pipefail

echo "========================================"
echo "  SDN 실습 환경 전체 정리 시작"
echo "========================================"

### ── K8s 클러스터 정리 ─────────────────────────────────────
echo "[1/4] kind 클러스터 정리..."
if command -v kind &>/dev/null; then
  kind delete cluster --name sdn-lab 2>/dev/null && echo "  ✅  kind 클러스터 삭제" || echo "  ↳  클러스터 없음"
fi

### ── Mininet 정리 ───────────────────────────────────────────
echo "[2/4] Mininet 환경 정리..."
if command -v mn &>/dev/null; then
  sudo mn -c 2>/dev/null && echo "  ✅  Mininet 정리 완료" || true
fi

### ── OVS 브리지 + 네임스페이스 정리 ───────────────────────
echo "[3/4] OVS 브리지 및 네임스페이스 정리..."
for BR in br-sdn br0; do
  sudo ovs-vsctl del-br "${BR}" 2>/dev/null && echo "  ✅  브리지 ${BR} 삭제" || true
done
for NS in ns-h1 ns-h2 ns-h3 host1 host2; do
  sudo ip netns del "${NS}" 2>/dev/null && echo "  ✅  네임스페이스 ${NS} 삭제" || true
done

### ── KVM VM 정리 ────────────────────────────────────────────
echo "[4/4] KVM VM 정리..."
for VM in vm-controller vm-worker1 vm-worker2; do
  sudo virsh destroy  "${VM}" 2>/dev/null || true
  sudo virsh undefine "${VM}" --remove-all-storage 2>/dev/null \
    && echo "  ✅  VM ${VM} 삭제" || true
done
sudo virsh net-destroy  sdn-net 2>/dev/null || true
sudo virsh net-undefine sdn-net 2>/dev/null \
  && echo "  ✅  sdn-net 네트워크 삭제" || true

echo ""
echo "========================================"
echo "✅  전체 정리 완료!"
echo "========================================"
```

---

## 📁 전체 파일 구성 요약
```
sdn-lab/
├── 00_kvm_setup.sh      # KVM + VM 3개 생성 (로컬 PC에서 실행)
├── 01_mininet.sh        # Mininet 설치/실습  → vm-worker1
├── 02_odl.sh            # OpenDaylight 설치  → vm-controller
├── 03_ovs.sh            # OVS 심화 실습      → vm-worker2
├── 04_k8s_setup.sh      # kind + Calico       → vm-controller
├── 05_cnf.sh            # vFirewall + MetalLB → vm-controller
└── 99_cleanup.sh        # 전체 정리 (로컬 PC)