#!/bin/bash
#=========================================================================
# Cephadm 초기 설정 및 호스트 준비 스크립트
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

# 인자 받기
NETWORK_PREFIX=$1
WORKER_LENGTH=$2
SSH_PASSWORD=$3
CEPH_VERSION=$4
NUM_MON=3 # 소규모 클러스터 권장 수량
NUM_MGR=2 # 소규모 클러스터 권장 수량

echo "Ceph 버전: $CEPH_VERSION, 네트워크: $NETWORK_PREFIX 워커 노드 수: $WORKER_LENGTH"

# 마스터 노드 설정
MASTER_IP="${NETWORK_PREFIX}.10"
MASTER_HOSTNAME="k8s-master"

#=========================================================================
# 1. 노드 설정 및 초기화
#=========================================================================
echo -e "\n[단계 1/6] 노드 설정 및 초기화를 시작합니다..."

# 워커 노드 배열 초기화
echo ">> 워커 노드 설정 초기화 중..."
WORKER_NODES=()
# 워커 노드 설정을 for 루프로 처리
for i in $(seq 1 $WORKER_LENGTH); do
  WORKER_IP="${NETWORK_PREFIX}.$((i + 10))"
  WORKER_HOSTNAME="k8s-worker-${i}"
  WORKER_NODES+=("$WORKER_HOSTNAME")
done

#=========================================================================
# 2. 필수 패키지 설치
#=========================================================================
echo -e "\n[단계 2/6] 필수 패키지 설치를 시작합니다..."

# APT 업데이트가 최근에 실행되었는지 확인
echo ">> APT 업데이트 확인 중..."
if [ ! -f /var/tmp/apt_updated ] || [ "$(find /var/tmp/apt_updated -mmin +30)" ]; then
    echo ">> APT 업데이트 실행 중..."
    apt-get update
    date "+%Y-%m-%d %H:%M:%S" > /var/tmp/apt_updated
fi

# Ceph 관련 필수 패키지 설치
echo ">> Ceph 관련 패키지 설치 중..."

# Python3 및 필요한 패키지 설치
apt-get install -y python3 python3-pip python3-venv python3-setuptools

# Ceph 관련 패키지 설치
apt-get install -y curl wget gnupg sshpass expect cephadm ceph-common lvm2

# Helm 설치 (cephfs, rbd에서 필요)
if ! command -v helm &> /dev/null; then
    echo ">> Helm 설치 중..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
fi

# Helm 저장소 추가 (cephfs, rbd에서 사용)
echo ">> Helm 저장소 추가 중..."
helm repo add ceph-csi https://ceph.github.io/csi-charts
helm repo update

# jq 설치 (object storage에서 필요)
apt-get install -y jq

# cephadm 설치
if ! command -v cephadm &> /dev/null; then
    echo ">> cephadm 설치 중..."
    curl --silent --remote-name --location https://github.com/ceph/ceph/raw/${CEPH_VERSION}/src/cephadm/cephadm
    chmod +x cephadm
    ./cephadm add-repo --release ${CEPH_VERSION}
    ./cephadm install
fi

#=========================================================================
# 3. 네트워크 설정
#=========================================================================
echo -e "\n[단계 3/6] 네트워크 설정을 시작합니다..."

# /etc/hosts 업데이트
echo ">> /etc/hosts 파일 업데이트 중..."
grep -q "$MASTER_IP $MASTER_HOSTNAME" /etc/hosts || echo "$MASTER_IP $MASTER_HOSTNAME" | sudo tee -a /etc/hosts

# 워커 노드 hosts 추가
for i in $(seq 1 $WORKER_LENGTH); do
  WORKER_IP="${NETWORK_PREFIX}.$((i + 10))"
  WORKER_HOSTNAME="k8s-worker-${i}"
  grep -q "$WORKER_IP $WORKER_HOSTNAME" /etc/hosts || echo "$WORKER_IP $WORKER_HOSTNAME" | sudo tee -a /etc/hosts
done

#=========================================================================
# 4. SSH 키 설정 및 배포
#=========================================================================
echo -e "\n[단계 4/6] SSH 키 설정 및 배포를 시작합니다..."

# SSH 키 설정
echo ">> SSH 키 생성 중..."
if [ ! -f /root/.ssh/id_rsa ]; then
    sudo ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
fi

# 올바른 권한 설정
sudo chmod 600 /root/.ssh/id_rsa
sudo chmod 644 /root/.ssh/id_rsa.pub

# worker 노드에 SSH 키 배포
echo ">> 워커 노드에 SSH 키 배포 중..."
for host in "${WORKER_NODES[@]}"; do
    ip=$(getent hosts $host | awk '{print $1}')
    echo ">> SSH 키 배포: $host ($ip)"
    
    # SSH 키 복사
    sshpass -p "$SSH_PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no root@$ip
    
    # 연결 테스트
    ssh -o StrictHostKeyChecking=no root@$ip "echo 'SSH 연결 성공: \$(hostname)'"
done

# 시간 동기화 서비스 설치 및 구성
echo ">> 시간 동기화 서비스 설정 중..."
apt-get install -y chrony
systemctl restart chrony
systemctl enable chrony

# worker 노드에도 Ceph 관련 패키지 및 시간 동기화 설치
echo ">> 워커 노드에 Ceph 패키지 설치 중..."
for host in "${WORKER_NODES[@]}"; do
    ip=$(getent hosts $host | awk '{print $1}')
    echo ">> 노드 $host ($ip)에 패키지 설치 중..."
    
    # 워커 노드의 APT 업데이트 상태 확인 및 필요시 업데이트
    ssh -o StrictHostKeyChecking=no root@$ip 'if [ ! -f /var/tmp/apt_updated ] || [ "$(find /var/tmp/apt_updated -mmin +30)" ]; then apt-get update && date "+%Y-%m-%d %H:%M:%S" > /var/tmp/apt_updated; fi'
    
    # Python 및 Ceph 관련 패키지 설치 (ceph-fuse 포함)
    ssh -o StrictHostKeyChecking=no root@$ip "apt-get install -y python3 python3-pip ceph-common ceph-fuse lvm2 chrony"
    
    # 시간 동기화 설정
    scp /etc/chrony/chrony.conf root@$ip:/etc/chrony/chrony.conf
    ssh -o StrictHostKeyChecking=no root@$ip "systemctl restart chrony && systemctl enable chrony"
done

#=========================================================================
# 5. Ceph 클러스터 부트스트랩
#=========================================================================
echo -e "\n[단계 5/6] Ceph 클러스터 부트스트랩을 시작합니다..."

# Ceph 부트스트랩
echo ">> Ceph 클러스터 부트스트랩 중..."
sudo cephadm bootstrap --mon-ip $MASTER_IP --ssh-private-key /root/.ssh/id_rsa --ssh-public-key /root/.ssh/id_rsa.pub

# 컨테이너 엔진 설치
echo ">> 컨테이너 엔진 설치 중..."
apt-get install -y podman
for host in "${WORKER_NODES[@]}"; do
    ip=$(getent hosts $host | awk '{print $1}')
    echo ">> 노드 $host에 컨테이너 엔진 설치 중..."
    
    ssh -o StrictHostKeyChecking=no root@$ip "apt-get install -y podman"
    ssh -o StrictHostKeyChecking=no root@$ip "sudo systemctl restart podman"
done

# Ceph 호스트 추가
echo ">> Ceph 호스트 추가 중..."
for i in $(seq 1 $WORKER_LENGTH); do
    host="k8s-worker-$i"
    ip="${NETWORK_PREFIX}.$((i + 10))"
    echo ">> 호스트 추가: $host ($ip)"
    ceph orch host add $host $ip
done

# 모니터 및 매니저 배포
echo ">> 모니터 배포 중..."
ceph orch apply mon --placement=$NUM_MON

echo ">> 매니저 배포 중..."
ceph orch apply mgr --placement=$NUM_MGR

#=========================================================================
# 6. OSD 디스크 준비 및 배포
#=========================================================================
echo -e "\n[단계 6/6] OSD 디스크 준비 및 배포를 시작합니다..."

# OSD 디스크 준비 (간소화)
echo ">> OSD 디스크 준비 중..."
for i in $(seq 1 $WORKER_LENGTH); do
    host="k8s-worker-$i"
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

echo -e "\n[완료] Ceph 클러스터 설치가 완료되었습니다."