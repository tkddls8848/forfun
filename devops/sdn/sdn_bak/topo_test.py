# topo_test.py
from mininet.topo import Topo
from mininet.net import Mininet
from mininet.node import OVSSwitch, Controller
from mininet.cli import CLI

class MyTopo(Topo):
    def build(self):
        # 스위치 2개
        s1 = self.addSwitch('s1')
        s2 = self.addSwitch('s2')
        # 호스트 4개
        h1 = self.addHost('h1', ip='10.0.0.1/24')
        h2 = self.addHost('h2', ip='10.0.0.2/24')
        h3 = self.addHost('h3', ip='10.0.0.3/24')
        h4 = self.addHost('h4', ip='10.0.0.4/24')
        # 링크 연결
        self.addLink(h1, s1)
        self.addLink(h2, s1)
        self.addLink(h3, s2)
        self.addLink(h4, s2)
        self.addLink(s1, s2)

if __name__ == '__main__':
    topo = MyTopo()
    net = Mininet(topo=topo, switch=OVSSwitch)
    net.start()
    CLI(net)
    net.stop()


sudo python3 topo_test.py
mininet> h1 ping h4   # 스위치 넘어서 핑 확인
mininet> h1 iperf h4  # 대역폭 확인