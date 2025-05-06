#!/bin/bash

set -e

# OSD 디스크 수와 워커 노드 수를 인자로 받음
OSD_NUM=$1
WORKER_LENGTH=$2
SSH_PASSWORD=$3

echo "Ceph OSD 디스크 수: $OSD_NUM, 워커 노드 수: $WORKER_LENGTH"

# 필요한 패키지 설치
apt-get update
apt-get install -y curl wget lvm2 expect

for i in $(seq 1 $WORKER_LENGTH); do
  worker="k8s-worker-$i"
  echo "==== $worker 노드의 디스크 준비 시작 ===="
  # 각 디스크 장치명 생성 및 명령어 구성
  for j in $(seq 1 $OSD_NUM); do
    CHAR_CODE=$((97 + j))  # ASCII 'b'부터 시작 (a는 시스템 디스크)
    DISK="/dev/sd$(printf "\$(printf '%03o' $CHAR_CODE)")"
    
    REMOTE_CMD="
    echo \"디스크 $DISK 준비 중...\"
    sgdisk --zap-all $DISK
    echo \"디스크 $DISK 준비 완료\"
    "
    # expect를 사용하여 SSH 자동화
    expect -c "
    set timeout 60
    spawn ssh -o StrictHostKeyChecking=no root@$worker
    expect {
      \"password:\" {
        send \"$SSH_PASSWORD\r\"
        expect \"*#*\"
        send \"$REMOTE_CMD\r\"
        expect \"*#*\"
        send \"exit\r\"
      }
      \"*#*\" {
        send \"$REMOTE_CMD\r\"
        expect \"*#*\"
        send \"exit\r\"
      }
      timeout {
        puts \"SSH 연결 시간 초과: $worker\"
        exit 1
      }
    }
    expect eof
    "
  done
  echo "==== $worker 노드의 디스크 준비 완료 ===="
done

echo "모든 워커 노드의 디스크 준비 완료"
