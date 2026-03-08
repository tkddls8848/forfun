#!/bin/bash
# =============================================================
# 03_ovs.sh
# 역할: Open vSwitch 심화 실습
#       브리지 생성 → VLAN → 플로우룰 → 네임스페이스 가상 호스트
# 실행 위치: vm-worker2 (ssh sdn@192.168.100.12)
# 실행: sudo bash 03_ovs.sh
# =============================================================
set -euo pipefail

BRIDGE="br-sdn"
VLAN100_IP1="10.100.0.1/24"
VLAN200_IP1="10.200.0.1/24"
VLAN100_IP2="10.100.0.2/24"
VLAN200_IP2="10.200.0.2/24"

### ── 0. 기존 환경 정리 ──────────────────────────────────────
cleanup() {
  echo "[CLEANUP] 기존 OVS 환경 정리..."
  ovs-vsctl del-br "${BRIDGE}" 2>/dev/null || true
  ip netns del ns-h1 2>/dev/null || true
  ip netns del ns-h2 2>/dev/null || true
  ip netns del ns-h3 2>/dev/null || true
  ip link del veth-h1  2>/dev/null || true
  ip link del veth-h2  2>/dev/null || true
  ip link del veth-h3  2>/dev/null || true
}
cleanup

### ── 1. OVS 설치 및 서비스 시작 ────────────────────────────
echo "[1/5] Open vSwitch 설치 및 시작..."
apt update -qq
apt install -y openvswitch-switch openvswitch-common
systemctl enable --now openvswitch-switch
ovs-vsctl show
echo "✅  OVS 설치 완료"

### ── 2. 브리지 + VLAN 포트 구성 ────────────────────────────
echo "[2/5] 브리지 + VLAN 구성 중..."

ovs-vsctl add-br "${BRIDGE}"
ovs-vsctl set bridge "${BRIDGE}" protocols=OpenFlow13

# 네트워크 네임스페이스 생성
for NS in ns-h1 ns-h2 ns-h3; do
  ip netns add "${NS}"
done

# veth 페어 생성 및 네임스페이스 연결
create_veth() {
  local ns=$1 veth=$2 veth_br=$3 tag=$4 ip=$5
  ip link add "${veth}"    type veth peer name "${veth_br}"
  ip link set "${veth}"    netns "${ns}"
  ip link set "${veth_br}" up
  ovs-vsctl add-port "${BRIDGE}" "${veth_br}" tag="${tag}"
  ip netns exec "${ns}" ip link set lo      up
  ip netns exec "${ns}" ip link set "${veth}" up
  ip netns exec "${ns}" ip addr add "${ip}" dev "${veth}"
}

create_veth ns-h1 veth-h1 veth-h1-br 100 "${VLAN100_IP1}"   # VLAN100
create_veth ns-h2 veth-h2 veth-h2-br 100 "${VLAN100_IP2}"   # VLAN100 (같은 VLAN)
create_veth ns-h3 veth-h3 veth-h3-br 200 "${VLAN200_IP1}"   # VLAN200 (다른 VLAN)

echo "✅  VLAN 구성 완료"
ovs-vsctl show

### ── 3. OpenFlow 플로우룰 추가 ─────────────────────────────
echo "[3/5] OpenFlow 플로우룰 추가 중..."

# ARP 허용
ovs-ofctl -O OpenFlow13 add-flow "${BRIDGE}" \
  "priority=100,arp,actions=NORMAL"

# ICMP (ping) 허용
ovs-ofctl -O OpenFlow13 add-flow "${BRIDGE}" \
  "priority=90,ip,nw_proto=1,actions=NORMAL"

# h1 → h2 TCP 포트 8080 차단 (방화벽 규칙 예시)
H1_MAC=$(ip netns exec ns-h1 ip link show veth-h1 | awk '/ether/{print $2}')
ovs-ofctl -O OpenFlow13 add-flow "${BRIDGE}" \
  "priority=200,ip,dl_src=${H1_MAC},nw_proto=6,tp_dst=8080,actions=drop"

# 나머지 IP 트래픽 정상 포워딩
ovs-ofctl -O OpenFlow13 add-flow "${BRIDGE}" \
  "priority=10,ip,actions=NORMAL"

echo "✅  플로우룰 추가 완료"
ovs-ofctl -O OpenFlow13 dump-flows "${BRIDGE}"

### ── 4. 통신 테스트 ─────────────────────────────────────────
echo "[4/5] 통신 테스트 중..."

echo "  [테스트1] VLAN100 내부 통신 (h1 → h2, 성공해야 함):"
ip netns exec ns-h1 ping -c 3 10.100.0.2 && echo "  ✅  VLAN100 내부 통신 성공" || echo "  ❌  실패"

echo "  [테스트2] VLAN 간 통신 (h1 → h3, 실패해야 함):"
ip netns exec ns-h1 ping -c 2 -W 1 10.200.0.1 && echo "  ⚠️  예상과 다르게 성공" || echo "  ✅  VLAN 격리 정상 (예상된 실패)"

### ── 5. 상태 확인 명령어 안내 ──────────────────────────────
echo ""
echo "[5/5] 확인 명령어"
echo "========================================"
echo "  OVS 구성 확인:"
echo "    sudo ovs-vsctl show"
echo "    sudo ovs-ofctl -O OpenFlow13 dump-flows ${BRIDGE}"
echo "    sudo ovs-appctl fdb/show ${BRIDGE}"
echo ""
echo "  네임스페이스 접속:"
echo "    sudo ip netns exec ns-h1 bash"
echo "    sudo ip netns exec ns-h2 bash"
echo ""
echo "  플로우룰 추가 예시:"
echo "    sudo ovs-ofctl -O OpenFlow13 add-flow ${BRIDGE} \\"
echo "      'priority=50,ip,nw_dst=10.100.0.2,actions=output:1'"
echo ""
echo "  플로우룰 전체 삭제:"
echo "    sudo ovs-ofctl del-flows ${BRIDGE}"
echo "========================================"