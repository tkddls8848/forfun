#!/bin/bash

set -e

# 인자 받기
OSD_NUM=$1
NETWORK_PREFIX=$2
WORKER_LENGTH=$3
SSH_PASSWORD=$4
NUM_MON=3
NUM_MGR=2

echo "Ceph OSD 디스크 수: $OSD_NUM, 네트워크: $NETWORK_PREFIX 워커 노드 수: $WORKER_LENGTH"

# 마스터 노드 설정
MASTER_IP="${NETWORK_PREFIX}.10"
MASTER_HOSTNAME="k8s-master"

# 워커 노드 배열 초기화
WORKER_NODES=()
# 워커 노드 설정을 for 루프로 처리
for i in $(seq 1 $WORKER_LENGTH); do
  WORKER_IP="${NETWORK_PREFIX}.$((i + 10))"
  WORKER_HOSTNAME="k8s-worker-${i}"
  WORKER_NODES+=("$WORKER_HOSTNAME")
done

# Ceph 관련 필수 패키지 설치
echo "Ceph 관련 패키지 설치 중..."
apt update 

# Python3 및 필요한 패키지 설치
apt install -y python3 python3-pip python3-venv python3-setuptools

# Ceph 관련 패키지 설치
apt install -y curl wget gnupg sshpass expect cephadm ceph-common lvm2

# cephadm 설치
if ! command -v cephadm &> /dev/null; then
    curl --silent --remote-name --location https://github.com/ceph/ceph/raw/quincy/src/cephadm/cephadm
    chmod +x cephadm
    ./cephadm add-repo --release quincy
    ./cephadm install
fi

# /etc/hosts 업데이트
grep -q "$MASTER_IP $MASTER_HOSTNAME" /etc/hosts || echo "$MASTER_IP $MASTER_HOSTNAME" | sudo tee -a /etc/hosts

# 워커 노드 hosts 추가
for i in $(seq 1 $WORKER_LENGTH); do
  WORKER_IP="${NETWORK_PREFIX}.$((i + 10))"
  WORKER_HOSTNAME="k8s-worker-${i}"
  grep -q "$WORKER_IP $WORKER_HOSTNAME" /etc/hosts || echo "$WORKER_IP $WORKER_HOSTNAME" | sudo tee -a /etc/hosts
done

# SSH 키 설정
if [ ! -f /root/.ssh/id_rsa ]; then
    sudo ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
fi

# 올바른 권한 설정
sudo chmod 600 /root/.ssh/id_rsa
sudo chmod 644 /root/.ssh/id_rsa.pub

# worker 노드에 SSH 키 배포
for host in "${WORKER_NODES[@]}"; do
    ip=$(getent hosts $host | awk '{print $1}')
    echo "SSH 키 배포: $host ($ip)"
    
    # SSH 비밀번호 인증 활성화
    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no root@$ip "sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config && systemctl restart sshd"
    
    # SSH 키 복사
    sshpass -p "$SSH_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no root@$ip
    
    # 연결 테스트
    ssh -o StrictHostKeyChecking=no root@$ip "echo 'SSH 연결 성공: \$(hostname)'"
done

# 시간 동기화 서비스 설치 및 구성
echo "시간 동기화 서비스 설정 중..."
apt-get install -y chrony
systemctl restart chrony
systemctl enable chrony

# worker 노드에도 Ceph 관련 패키지 및 시간 동기화 설치
for host in "${WORKER_NODES[@]}"; do
    ip=$(getent hosts $host | awk '{print $1}')
    echo "노드 $host ($ip)에 Ceph 패키지 및 시간 동기화 서비스 설치 중..."
    
    # Python 및 Ceph 관련 패키지 설치
    ssh -o StrictHostKeyChecking=no root@$ip "apt-get update && apt-get install -y python3 python3-pip ceph-common lvm2 chrony"
    
    # 시간 동기화 설정
    scp /etc/chrony/chrony.conf root@$ip:/etc/chrony/chrony.conf
    ssh -o StrictHostKeyChecking=no root@$ip "systemctl restart chrony && systemctl enable chrony"
done

# Ceph 부트스트랩
sudo cephadm bootstrap --mon-ip $MASTER_IP --ssh-private-key /root/.ssh/id_rsa --ssh-public-key /root/.ssh/id_rsa.pub

# 컨테이너 엔진 설치
apt-get update && apt-get install -y podman
for host in "${WORKER_NODES[@]}"; do
    ip=$(getent hosts $host | awk '{print $1}')
    echo "노드 $host에 컨테이너 엔진(podman) 설치 중..."
    
    ssh -o StrictHostKeyChecking=no root@$ip "apt-get update && apt-get install -y podman"
    ssh -o StrictHostKeyChecking=no root@$ip "sudo systemctl restart podman"
done

# Ceph 호스트 추가
for i in $(seq 1 $WORKER_LENGTH); do
    host="k8s-worker-$i"
    ip="${NETWORK_PREFIX}.$((i + 10))"
    ceph orch host add $host $ip
done

# 모니터 및 매니저 배포
echo "모니터 배포 중..."
ceph orch apply mon --placement=$NUM_MON

echo "매니저 배포 중..."
ceph orch apply mgr --placement=$NUM_MGR

# OSD 디스크 준비 (간소화)
echo "OSD 디스크 준비 중..."
for i in $(seq 1 $WORKER_LENGTH); do
    host="k8s-worker-$i"
    echo "==== $host 노드의 디스크 준비 중 ===="
    
    # 모든 추가 디스크 자동으로 찾아서 준비
    ssh -o StrictHostKeyChecking=no root@$host '
    for disk in $(lsblk -dn -o NAME | grep -E "sd[b-z]"); do
        echo "디스크 /dev/$disk 준비 중..."
        sgdisk --zap-all /dev/$disk
        echo "디스크 /dev/$disk 준비 완료"
    done
    '
    echo "==== $host 노드의 디스크 준비 완료 ===="
done

# 모든 사용 가능한 디바이스에 자동으로 OSD 배포
ceph orch apply osd --all-available-devices

echo "Ceph 클러스터 설치 완료"