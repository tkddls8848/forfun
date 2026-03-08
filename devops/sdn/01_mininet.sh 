#!/bin/bash
# =============================================================
# 01_mininet.sh
# 역할: Mininet 설치 + 커스텀 토폴로지 실습
# 실행 위치: vm-worker1 (ssh sdn@192.168.100.11)
# 실행: sudo bash 01_mininet.sh
# =============================================================
set -euo pipefail

### ── 1. 패키지 설치 ─────────────────────────────────────────
echo "[1/4] Mininet 설치 중..."
sudo apt update -qq
sudo apt install -y \
  mininet openvswitch-switch python3-pip \
  iperf3 tcpdump net-tools

pip3 install --quiet mininet 2>/dev/null || true

# 설치 확인
echo "    Mininet 버전: $(mn --version 2>&1 | head -1)"
echo "✅  Mininet 설치 완료"

### ── 2. 커스텀 토폴로지 파일 생성 ──────────────────────────
echo "[2/4] 커스텀 토폴로지 스크립트 생성 중..."

mkdir -p ~/sdn-lab/mininet
cat > ~/sdn-lab/mininet/topo_custom.py <<'PYEOF'
#!/usr/bin/env python3
# topo_custom.py
# 구성: 스위치 2개 + 호스트 4개 (첨부 topo_test.py 기반 확장)
from mininet.topo   import Topo
from mininet.net    import Mininet
from mininet.node   import OVSSwitch, Controller, RemoteController
from mininet.cli    import CLI
from mininet.log    import setLogLevel
from mininet.link   import TCLink

class SDNTopo(Topo):
    def build(self):
        # ── 스위치 ──────────────────────────────
        s1 = self.addSwitch('s1', protocols='OpenFlow13')
        s2 = self.addSwitch('s2', protocols='OpenFlow13')

        # ── 호스트 (대역폭/지연 링크 옵션 포함) ─
        h1 = self.addHost('h1', ip='10.0.0.1/24')
        h2 = self.addHost('h2', ip='10.0.0.2/24')
        h3 = self.addHost('h3', ip='10.0.0.3/24')
        h4 = self.addHost('h4', ip='10.0.0.4/24')

        # ── 링크 (100Mbps, 지연 5ms) ────────────
        linkopts = dict(bw=100, delay='5ms', use_htb=True)
        self.addLink(h1, s1, **linkopts)
        self.addLink(h2, s1, **linkopts)
        self.addLink(h3, s2, **linkopts)
        self.addLink(h4, s2, **linkopts)
        self.addLink(s1, s2, bw=1000, delay='1ms', use_htb=True)  # 스위치 간 업링크

def run_local():
    """로컬 컨트롤러(내장)로 실행"""
    setLogLevel('info')
    topo = SDNTopo()
    net  = Mininet(topo=topo, switch=OVSSwitch, link=TCLink)
    net.start()
    print("\n[테스트 시작]")
    print("  pingall →", end=" "); net.pingAll()
    CLI(net)
    net.stop()

def run_remote(controller_ip='192.168.100.10', port=6633):
    """ODL 외부 컨트롤러로 실행 (2단계와 연동)"""
    setLogLevel('info')
    topo = SDNTopo()
    net  = Mininet(
        topo=topo,
        switch=OVSSwitch,
        link=TCLink,
        controller=lambda name: RemoteController(name, ip=controller_ip, port=port)
    )
    net.start()
    CLI(net)
    net.stop()

if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == 'remote':
        run_remote()
    else:
        run_local()
PYEOF

chmod +x ~/sdn-lab/mininet/topo_custom.py
echo "✅  토폴로지 스크립트 생성: ~/sdn-lab/mininet/topo_custom.py"

### ── 3. 트리 토폴로지 빠른 테스트 ──────────────────────────
echo "[3/4] 기본 트리 토폴로지 연결 테스트 (자동 pingall 후 종료)..."
sudo mn --topo tree,2 \
        --switch  ovs,protocols=OpenFlow13 \
        --test    pingall
echo "✅  기본 토폴로지 테스트 완료"

### ── 4. 실습 가이드 출력 ────────────────────────────────────
echo ""
echo "[4/4] 실습 명령어 안내"
echo "========================================"
echo "  [기본 트리 토폴로지 실행]"
echo "    sudo mn --topo tree,2"
echo ""
echo "  [커스텀 토폴로지 - 로컬 컨트롤러]"
echo "    sudo python3 ~/sdn-lab/mininet/topo_custom.py"
echo ""
echo "  [커스텀 토폴로지 - ODL 연동 (2단계 설치 후)]"
echo "    sudo python3 ~/sdn-lab/mininet/topo_custom.py remote"
echo ""
echo "  [Mininet 내부 주요 명령어]"
echo "    mininet> nodes        # 노드 목록"
echo "    mininet> links        # 링크 목록"
echo "    mininet> pingall      # 전체 핑"
echo "    mininet> h1 ping h4   # 특정 핑"
echo "    mininet> iperf h1 h4  # 대역폭 테스트"
echo "    mininet> h1 tcpdump -i h1-eth0 &  # 패킷 캡처"
echo "    mininet> exit"
echo ""
echo "  [정리]"
echo "    sudo mn -c"
echo "========================================"