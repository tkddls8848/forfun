#!/bin/bash
#=========================================================================
# Ceph 클러스터 초기화 스크립트 (마스터 노드 전용)
# - Ceph 클러스터 부트스트랩
# - 호스트 추가 및 서비스 배포
# - OSD 디스크 준비 및 배포
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

# 인자 받기
NETWORK_PREFIX=$1
WORKER_LENGTH=$2
SSH_PASSWORD=$3
CEPH_VERSION=$4
NUM_MON=$5  # Vagrantfile에서 전달받은 모니터 개수
NUM_MGR=$6  # Vagrantfile에서 전달받은 매니저 개수

echo "=========================================="
echo "Ceph 클러스터 초기화 시작"
echo "=========================================="
echo "Ceph 버전: $CEPH_VERSION"
echo "네트워크 대역: $NETWORK_PREFIX"
echo "워커 노드 수: $WORKER_LENGTH"
echo "모니터 개수: $NUM_MON"
echo "매니저 개수: $NUM_MGR"
echo "=========================================="

# 마스터 노드 설정
MASTER_IP="${NETWORK_PREFIX}.10"
MASTER_HOSTNAME="ceph-master"

#=========================================================================
# 1. 노드 설정 및 초기화
#=========================================================================
echo -e "\n[단계 1/4] 노드 설정 및 초기화를 시작합니다..."

# 워커 노드 배열 초기화
echo ">> 워커 노드 설정 초기화 중..."
WORKER_NODES=()
for i in $(seq 1 $WORKER_LENGTH); do
  WORKER_HOSTNAME="ceph-worker-${i}"
  WORKER_NODES+=("$WORKER_HOSTNAME")
done

#=========================================================================
# 2. SSH 키 설정 및 배포
#=========================================================================
echo -e "\n[단계 2/4] SSH 키 설정 및 배포를 시작합니다..."

# SSH 키 생성 (root 계정용)
echo ">> SSH 키 생성 중..."
if [ ! -f /root/.ssh/id_rsa ]; then
    sudo ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ""
fi

# SSH 키 권한 설정
echo ">> SSH 키 권한 설정 중..."
sudo chmod 600 /root/.ssh/id_rsa
sudo chmod 644 /root/.ssh/id_rsa.pub

# 워커 노드에 SSH 키 배포
echo ">> 워커 노드에 SSH 키 배포 중..."
for host in "${WORKER_NODES[@]}"; do
    ip=$(getent hosts $host | awk '{print $1}')
    echo ">> SSH 키 배포: $host ($ip)"
    
    # 워커 노드 SSH 설정 수정 (root 로그인 및 비밀번호 인증 활성화)
    echo ">> $host 노드 SSH 설정 수정 중..."
    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no vagrant@$ip << 'EOF'
        # root 비밀번호 설정
        echo "root:vagrant" | sudo chpasswd
        
        # sudo 권한 부여
        echo "vagrant ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers
        
        # SSH 설정 수정
        echo "PermitRootLogin yes" | sudo tee -a /etc/ssh/sshd_config
        echo "PasswordAuthentication yes" | sudo tee -a /etc/ssh/sshd_config
        
        # SSH 서비스 재시작
        sudo systemctl restart ssh
        sudo systemctl restart sshd
EOF
    
    # SSH 키 복사
    sshpass -p "$SSH_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no root@$ip
done

#=========================================================================
# 3. Ceph 클러스터 부트스트랩 (Podman 사용)
#=========================================================================
echo -e "\n[단계 3/4] Ceph 클러스터 부트스트랩을 시작합니다..."

# Ceph 저장소 추가 (cephadm-setup.sh에서 이미 처리됨)
echo ">> Ceph 저장소 확인 중..."
if [ ! -f /usr/share/keyrings/ceph-archive-keyring.gpg ]; then
    echo ">> Ceph 저장소 추가 중..."
    curl -fsSL https://download.ceph.com/keys/release.asc | gpg --dearmor -o /usr/share/keyrings/ceph-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/ceph-archive-keyring.gpg] https://download.ceph.com/debian-${CEPH_VERSION} $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/ceph.list
    apt-get update
fi

# Ceph 부트스트랩 (Podman 사용) - 내부 네트워크 설정 추가
echo ">> Ceph 클러스터 부트스트랩 중..."
sudo cephadm bootstrap \
  --mon-ip $MASTER_IP \
  --ssh-private-key /root/.ssh/id_rsa \
  --ssh-public-key /root/.ssh/id_rsa.pub \
  --cluster-network ${NETWORK_PREFIX}.0/24

# Ceph 호스트 추가
echo ">> Ceph 호스트 추가 중..."
for i in $(seq 1 $WORKER_LENGTH); do
    host="ceph-worker-$i"
    ip="${NETWORK_PREFIX}.$((i + 10))"
    echo ">> 호스트 추가: $host ($ip)"
    ceph orch host add $host $ip
done

# 모니터 및 매니저 배포
echo ">> 모니터 배포 중..."
ceph orch apply mon --placement=$NUM_MON

echo ">> 매니저 배포 중..."
ceph orch apply mgr --placement=$NUM_MGR

# 클러스터 기본 복제 계수를 2로 설정
echo ">> 클러스터 기본 복제 계수를 2로 설정 중..."
ceph config set global osd_pool_default_size 2

#=========================================================================
# 4. OSD 디스크 준비 및 배포
#=========================================================================
echo -e "\n[단계 4/4] OSD 디스크 준비 및 배포를 시작합니다..."

# OSD 디스크 준비 (간소화)
echo ">> OSD 디스크 준비 중..."
for i in $(seq 1 $WORKER_LENGTH); do
    host="ceph-worker-$i"
    echo ">> $host 노드의 디스크 준비 중..."
    
    # 모든 추가 디스크 자동으로 찾아서 준비
    ssh -o StrictHostKeyChecking=no root@$host '
    for disk in $(lsblk -dn -o NAME | grep -E "sd[b-z]"); do
        echo "   디스크 /dev/$disk 준비 중..."
        sgdisk --zap-all /dev/$disk
        echo "   디스크 /dev/$disk 준비 완료"
    done
    '
    echo ">> $host 노드의 디스크 준비 완료"
done

# 모든 사용 가능한 디바이스에 자동으로 OSD 배포
echo ">> OSD 배포 중..."
ceph orch apply osd --all-available-devices

echo -e "\n[완료] Ceph 클러스터 초기화가 완료되었습니다."
echo "=========================================="
echo "Ceph 클러스터 상태 확인:"
echo "  - 클러스터 상태: ceph -s"
echo "  - 서비스 상태: ceph orch ls"
echo "  - OSD 상태: ceph osd status"
echo "=========================================="