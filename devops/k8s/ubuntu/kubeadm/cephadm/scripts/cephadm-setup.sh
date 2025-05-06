#!/bin/bash

set -e

apt update 
apt install -y curl wget gnupg sshpass expect cephadm ceph-common

# cephadm 설치
curl --silent --remote-name --location https://github.com/ceph/ceph/raw/quincy/src/cephadm/cephadm
chmod +x cephadm
./cephadm add-repo --release quincy
./cephadm install 

#OSD_NUM=$1
#NETWORK_PREFIX=$2
#WORKER_LENGTH=$3
OSD_NUM=2
NETWORK_PREFIX="192.168.56"
WORKER_LENGTH=3
echo "Ceph OSD 디스크 수: $OSD_NUM, 네트워크: $NETWORK_PREFIX 워커 노드 수: $WORKER_LENGTH"

# 마스터 노드 설정
MASTER_IP="${NETWORK_PREFIX}.10"
MASTER_HOSTNAME="k8s-master"

# /etc/hosts에 마스터 노드 추가
grep -q "$MASTER_IP $MASTER_HOSTNAME" /etc/hosts || echo "$MASTER_IP $MASTER_HOSTNAME" | sudo tee -a /etc/hosts

# 워커 노드 배열 초기화
WORKER_NODES=()
# 워커 노드 설정을 for 루프로 처리
for i in $(seq 1 $WORKER_LENGTH); do
  WORKER_IP="${NETWORK_PREFIX}.$((i + 10))"
  WORKER_HOSTNAME="k8s-worker-${i}"
  WORKER_NODES+=("$WORKER_HOSTNAME")
  # /etc/hosts에 워커 노드 추가
  grep -q "$WORKER_IP $WORKER_HOSTNAME" /etc/hosts || echo "$WORKER_IP $WORKER_HOSTNAME" | sudo tee -a /etc/hosts
done

# 한 가지 사용자(root)만 사용하여 일관성 유지
sudo ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa || true
SSH_KEY=$(cat /root/.ssh/id_rsa.pub)

# 올바른 권한 설정
sudo chmod 600 /root/.ssh/id_rsa
sudo chmod 644 /root/.ssh/id_rsa.pub

# worker 노드에도 동일한 설정 적용
for host in "${WORKER_NODES[@]}"; do
  ip=$(getent hosts $host | awk '{print $1}')
  echo "SSH 키 배포: $host ($ip)"  
  # SSH 키 배포 전 worker 노드에서 SSH 설정 확인
  sshpass -p "vagrant" ssh -o StrictHostKeyChecking=no root@$ip "sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config && systemctl restart sshd"
  # sshpass를 사용하여 비밀번호 인증으로 SSH 키 복사
  sshpass -p "vagrant" ssh-copy-id -o StrictHostKeyChecking=no root@$ip  
  # 연결 테스트
  ssh -o StrictHostKeyChecking=no root@$ip "echo 'SSH 연결 성공: \$(hostname)'"
done

# 시간 동기화 서비스 설치 및 구성 추가
echo "시간 동기화 서비스 설정 중..."
sudo apt-get install -y chrony

# chrony 서비스 재시작 및 활성화
sudo systemctl restart chrony
sudo systemctl enable chrony

# worker 노드에도 동일한 설정 적용
for host in "${WORKER_NODES[@]}"; do
  ip=$(getent hosts $host | awk '{print $1}')
  echo "노드 $host ($ip)에 시간 동기화 서비스 설치 중..."  
  # 원격 노드에 chrony 설치
  ssh -o StrictHostKeyChecking=no root@$ip "apt-get update && apt-get install -y chrony"  
  # chrony 구성 파일 전송
  scp /etc/chrony/chrony.conf root@$ip:/etc/chrony/chrony.conf  
  # 서비스 재시작
  ssh -o StrictHostKeyChecking=no root@$ip "systemctl restart chrony && systemctl enable chrony"  
  # 동기화 상태 확인
  ssh -o StrictHostKeyChecking=no root@$ip "chronyc tracking"
done

# Ceph 부트스트랩 (실제 키 경로 지정)
sudo cephadm bootstrap --mon-ip $MASTER_IP --ssh-private-key /root/.ssh/id_rsa --ssh-public-key /root/.ssh/id_rsa.pub

# SSH 키 배포 후, 컨테이너 엔진 설치
apt-get update && apt-get install -y podman
for host in "${WORKER_NODES[@]}"; do
  ip=$(getent hosts $host | awk '{print $1}')
  echo "노드 $host에 컨테이너 엔진(podman) 설치 중..."
  
  # podman 설치 (또는 Docker를 선호한다면 docker.io 패키지로 변경 가능)
  ssh -o StrictHostKeyChecking=no root@$ip "apt-get update && apt-get install -y podman"
  ssh -o StrictHostKeyChecking=no root@$ip "sudo systemctl restart podman"
  
  echo "컨테이너 엔진 설치 완료: $host"
done

# SSH 연결 테스트 후 Ceph 호스트 추가
ceph orch host add k8s-worker-1 192.168.56.11
ceph orch host add k8s-worker-2 192.168.56.12
ceph orch host add k8s-worker-3 192.168.56.13

# 추가 모니터 배포 (총 3개)
echo "모니터 배포 중..."
ceph orch apply mon --placement=3

# 추가 매니저 배포 (총 2개)
echo "매니저 배포 중..."
ceph orch apply mgr --placement=2

# 모든 사용 가능한 디바이스에 자동으로 OSD 배포
ceph orch apply osd --all-available-devices

