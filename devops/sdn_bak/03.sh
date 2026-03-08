sudo apt install -y openvswitch-switch
sudo systemctl start openvswitch-switch
sudo systemctl enable openvswitch-switch
sudo ovs-vsctl show  # 확인

# 브리지 생성
sudo ovs-vsctl add-br br0

# 가상 인터페이스 추가
sudo ovs-vsctl add-port br0 veth0
sudo ovs-vsctl add-port br0 veth1

# VLAN 설정
sudo ovs-vsctl set port veth0 tag=100
sudo ovs-vsctl set port veth1 tag=200

# 구성 확인
sudo ovs-vsctl show

# 특정 포트로 트래픽 포워딩 규칙 추가
sudo ovs-ofctl add-flow br0 \
  "in_port=1,dl_type=0x0800,nw_dst=10.0.0.2,actions=output:2"

# 규칙 확인
sudo ovs-ofctl dump-flows br0

# 규칙 삭제
sudo ovs-ofctl del-flows br0

# 네임스페이스로 가상 호스트 만들기
sudo ip netns add host1
sudo ip netns add host2

# veth 페어 생성
sudo ip link add veth-h1 type veth peer name veth-h1-br
sudo ip link add veth-h2 type veth peer name veth-h2-br

# 네임스페이스에 연결
sudo ip link set veth-h1 netns host1
sudo ip link set veth-h2 netns host2

# OVS 브리지에 연결
sudo ovs-vsctl add-port br0 veth-h1-br
sudo ovs-vsctl add-port br0 veth-h2-br

# IP 설정
sudo ip netns exec host1 ip addr add 10.0.0.1/24 dev veth-h1
sudo ip netns exec host2 ip addr add 10.0.0.2/24 dev veth-h2
sudo ip netns exec host1 ip link set veth-h1 up
sudo ip netns exec host2 ip link set veth-h2 up
sudo ip link set veth-h1-br up
sudo ip link set veth-h2-br up

# 통신 테스트
sudo ip netns exec host1 ping 10.0.0.2

sudo ovs-vsctl show          # 브리지/포트 구성
sudo ovs-ofctl dump-flows br0 # 플로우 테이블 확인
sudo ovs-appctl fdb/show br0  # MAC 테이블 확인