sudo apt update
sudo apt install -y mininet openvswitch-switch python3-pip
pip3 install mininet
sudo mn --version  # 설치 확인

# 트리 구조 토폴로지 (2계층)
sudo mn --topo tree,2

# 실행 후 기본 명령어
mininet> nodes        # 노드 목록 확인
mininet> links        # 링크 목록 확인
mininet> pingall      # 전체 핑 테스트
mininet> iperf        # 대역폭 테스트
mininet> exit