#!/bin/bash
#=========================================================================
# Ceph 클러스터 공통 설치 스크립트 (워커/마스터 노드 공통)
# - 시스템 기본 설정
# - Podman 설치 및 설정
# - SSH 설정
# - 네트워크 설정
# - Ceph 공통 패키지 설치
# - 노드별 특화 설정
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

# 비대화형 설치를 위한 환경 변수 설정 (스크립트 시작 시)
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# 인자 받기
MASTER_IP=$1
NETWORK_PREFIX=$2
WORKER_LENGTH=$3

# 노드 타입 확인 (호스트명으로 판단)
NODE_TYPE="worker"
if [[ $(hostname) == "ceph-master" ]]; then
    NODE_TYPE="master"
fi

echo "=========================================="
echo "Ceph 클러스터 공통 설치 스크립트 시작"
echo "=========================================="
echo "마스터 IP: $MASTER_IP"
echo "네트워크: $NETWORK_PREFIX"
echo "워커 노드 수: $WORKER_LENGTH"
echo "현재 노드 타입: $NODE_TYPE"
echo "현재 호스트명: $(hostname)"
echo "=========================================="

#=========================================================================
# 1. 시스템 업데이트 (공통)
#=========================================================================
echo -e "\n[단계 1/7] 시스템 업데이트를 시작합니다..."

# APT 업데이트 (비대화형)
echo ">> APT 업데이트 중..."
apt-get update -y

# 기본 패키지 설치 (공통) - 비대화형
echo ">> 기본 패키지 설치 중..."
apt-get install -y -q curl wget gnupg2 software-properties-common apt-transport-https ca-certificates netcat

#=========================================================================
# 2. SSH 설정 (공통)
#=========================================================================
echo -e "\n[단계 2/7] SSH 설정을 시작합니다..."

# SSH 설정 파일 백업
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# SSH 비밀번호 인증 활성화
echo ">> SSH 비밀번호 인증 활성화 중..."
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/#PasswordAuthentication no/' /etc/ssh/sshd_config

# Root 로그인 허용 (Vagrant 환경에서만)
echo ">> Root 로그인 허용 설정 중..."
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# SSH 서비스 재시작
echo ">> SSH 서비스 재시작 중..."
systemctl restart ssh

#=========================================================================
# 3. Podman 설치 (공통)
#=========================================================================
echo -e "\n[단계 3/7] Podman 설치를 시작합니다..."

# Podman 설치 (비대화형)
echo ">> Podman 설치 중..."
apt-get install -y -q podman

# Podman 서비스 활성화
echo ">> Podman 서비스 활성화 중..."
systemctl enable podman.socket
systemctl start podman.socket

# Podman 설치 확인
echo ">> Podman 설치 확인 중..."
if command -v podman &> /dev/null; then
    echo ">> Podman 설치 성공: $(podman --version)"
else
    echo ">> Podman 설치 실패"
    exit 1
fi

# Podman 레지스트리 설정
echo ">> Podman 레지스트리 설정 중..."
mkdir -p /etc/containers
cat > /etc/containers/registries.conf << EOF
unqualified-search-registries = ["docker.io"]
[[registry]]
prefix = "docker.io"
location = "docker.io"
EOF

# Podman 네트워크 설정 확인
echo ">> Podman 네트워크 설정 확인 중..."
podman network ls | grep -q podman || podman network create podman

# Podman 서비스 상태 확인
echo ">> Podman 서비스 상태 확인 중..."
systemctl is-active --quiet podman.socket || systemctl start podman.socket

#=========================================================================
# 4. Ceph 공통 패키지 설치 (공통)
#=========================================================================
echo -e "\n[단계 4/7] Ceph 공통 패키지 설치를 시작합니다..."

# Ceph 공통 패키지 설치 (비대화형)
echo ">> Ceph 공통 패키지 설치 중..."
apt-get install -y -q python3 python3-pip ceph-common ceph-fuse lvm2 jq

# 시간 동기화 서비스 설치 및 구성 (비대화형)
echo ">> 시간 동기화 서비스 설정 중..."
apt-get install -y -q chrony
systemctl restart chrony
systemctl enable chrony

#=========================================================================
# 5. 네트워크 설정 (공통)
#=========================================================================
echo -e "\n[단계 5/7] 네트워크 설정을 시작합니다..."

# /etc/hosts 업데이트
echo ">> /etc/hosts 파일 업데이트 중..."
MASTER_HOSTNAME="ceph-master"
grep -q "$MASTER_IP $MASTER_HOSTNAME" /etc/hosts || echo "$MASTER_IP $MASTER_HOSTNAME" | sudo tee -a /etc/hosts

# 워커 노드 hosts 추가
for i in $(seq 1 $WORKER_LENGTH); do
  WORKER_IP="${NETWORK_PREFIX}.$((i + 10))"
  WORKER_HOSTNAME="ceph-worker-${i}"
  grep -q "$WORKER_IP $WORKER_HOSTNAME" /etc/hosts || echo "$WORKER_IP $WORKER_HOSTNAME" | sudo tee -a /etc/hosts
done

#=========================================================================
# 6. 노드별 특화 설정
#=========================================================================
echo -e "\n[단계 6/7] 노드별 특화 설정을 시작합니다..."

if [[ $NODE_TYPE == "master" ]]; then
    echo ">> 마스터 노드 특화 설정 중..."
    
    # 마스터 노드용 추가 패키지 설치 (비대화형)
    echo ">> 마스터 노드용 패키지 설치 중..."
    apt-get install -y -q sshpass expect
    
    # Ceph 저장소 추가 (마스터 노드만)
    echo ">> Ceph 저장소 추가 중..."
    curl -fsSL https://download.ceph.com/keys/release.asc | gpg --dearmor -o /usr/share/keyrings/ceph-archive-keyring.gpg
    
    # cephadm 설치 (마스터 노드만) - 비대화형
    if ! command -v cephadm &> /dev/null; then
        echo ">> cephadm 설치 중..."
        apt-get install -y -q cephadm
    fi
    
    # 마스터 노드용 디렉토리 생성
    echo ">> 마스터 노드용 디렉토리 생성 중..."
    mkdir -p /opt/ceph/{config,logs,backup}
    
    echo ">> 마스터 노드 설정 완료"
    
else
    echo ">> 워커 노드 특화 설정 중..."
    
    # 워커 노드용 추가 패키지 설치 (비대화형)
    echo ">> 워커 노드용 패키지 설치 중..."
    apt-get install -y -q hdparm smartmontools
    
    # 워커 노드용 디렉토리 생성
    echo ">> 워커 노드용 디렉토리 생성 중..."
    mkdir -p /opt/ceph/{osd,logs}
    
    # OSD 디스크 확인 (워커 노드만)
    echo ">> OSD 디스크 확인 중..."
    lsblk | grep -E "sdb|sdc|sdd|sde" || echo ">> OSD 디스크가 아직 마운트되지 않았습니다."
    
    echo ">> 워커 노드 설정 완료"
fi

#=========================================================================
# 7. 환경 변수 및 설정 파일 준비 (공통)
#=========================================================================
echo -e "\n[단계 7/7] 환경 변수 및 설정 파일 준비를 시작합니다..."

# 환경 변수 설정 (이미 스크립트 시작 시 설정됨)
echo ">> 환경 변수 확인 중..."

# Ceph 관련 환경 변수 설정
cat >> /etc/environment << EOF
export CEPH_PUBLIC_NETWORK=${NETWORK_PREFIX}.0/24
export CEPH_CLUSTER_NETWORK=${NETWORK_PREFIX}.0/24
EOF

# needrestart 설정 개선
echo ">> needrestart 설정 개선 중..."
cat > /etc/needrestart/conf.d/50local.conf << EOF
\$nrconf{restart} = 'a';
\$nrconf{kernelhints} = -1;
EOF

#=========================================================================
# 설치 완료 요약
#=========================================================================
echo -e "\n=========================================="
echo "Ceph 클러스터 공통 설치 완료"
echo "=========================================="
echo "노드 타입: $NODE_TYPE"
echo "호스트명: $(hostname)"
echo "IP 주소: $(hostname -I | awk '{print $1}')"
echo "Podman 버전: $(podman --version)"
echo "설치된 패키지:"
echo "  - Podman: $(which podman)"
echo "  - SSH: $(systemctl is-active ssh)"
echo "  - Chrony: $(systemctl is-active chrony)"
echo "  - Ceph Common: $(which ceph)"
if [[ $NODE_TYPE == "master" ]]; then
    echo "  - Cephadm: $(which cephadm)"
fi
echo "=========================================="

echo -e "\n[완료] Ceph 클러스터 공통 설치가 완료되었습니다."
echo "다음 단계:"
if [[ $NODE_TYPE == "master" ]]; then
    echo "  - cephadm-setup.sh 실행 (Ceph 클러스터 초기화)"
else
    echo "  - 마스터 노드에서 Ceph 클러스터 초기화 대기"
fi 