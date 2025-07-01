#!/bin/bash
#=========================================================================
# Proxmox Ceph Squid 저장소 미러링 설정 스크립트
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

# 설정 변수
export MIRROR_BASE_URL="http://download.proxmox.com/debian/ceph-squid"
export MIRROR_LOCAL_PATH="/mnt/cephfs/proxmox-mirror"
export NGINX_CONFIG_PATH="/etc/nginx/sites-available/proxmox-mirror"
export NGINX_ENABLED_PATH="/etc/nginx/sites-enabled/proxmox-mirror"
export NGINX_PORT="8081"
export LOG_FILE="/var/log/proxmox-mirror.log"
export CRON_JOB_FILE="/etc/cron.d/proxmox-mirror"

# CephFS 마운트 포인트
export CEPHFS_MOUNT_POINT="/mnt/cephfs"

echo "Proxmox Ceph Squid 저장소 미러링 설정을 시작합니다..."

#=========================================================================
# 1. CephFS 마운트 확인 및 설정
#=========================================================================
echo -e "\n[단계 1/6] CephFS 마운트 확인 및 설정 중..."

# CephFS 마운트 확인
if ! mountpoint -q "$CEPHFS_MOUNT_POINT"; then
    echo ">> CephFS 마운트 중..."
    mkdir -p "$CEPHFS_MOUNT_POINT"
    ceph-fuse "$CEPHFS_MOUNT_POINT"
    echo ">> CephFS 마운트 완료"
else
    echo ">> CephFS가 이미 마운트되어 있습니다."
fi

# 미러 디렉토리 생성
echo ">> 미러 디렉토리 생성 중..."
mkdir -p "$MIRROR_LOCAL_PATH"

#=========================================================================
# 2. 필수 패키지 설치
#=========================================================================
echo -e "\n[단계 2/6] 필수 패키지 설치 중..."

# APT 업데이트
apt-get update

# 필수 패키지 설치
echo ">> nginx, wget, rsync 설치 중..."
apt-get install -y nginx wget rsync curl

#=========================================================================
# 3. 초기 미러링 스크립트 생성
#=========================================================================
echo -e "\n[단계 3/6] 미러링 스크립트 생성 중..."

cat > /usr/local/bin/proxmox-mirror-sync.sh << 'EOF'
#!/bin/bash
# Proxmox Ceph Squid 저장소 미러링 스크립트

set -e

# 설정 변수
MIRROR_BASE_URL="http://download.proxmox.com/debian/ceph-squid"
MIRROR_LOCAL_PATH="/mnt/cephfs/proxmox-mirror"
LOG_FILE="/var/log/proxmox-mirror.log"
LOCK_FILE="/var/run/proxmox-mirror.lock"

# 로그 함수
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 락 파일 확인
if [ -f "$LOCK_FILE" ]; then
    PID=$(cat "$LOCK_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        log_message "이미 실행 중인 미러링 프로세스가 있습니다. (PID: $PID)"
        exit 1
    else
        log_message "이전 프로세스가 비정상 종료되었습니다. 락 파일을 제거합니다."
        rm -f "$LOCK_FILE"
    fi
fi

# 락 파일 생성
echo $$ > "$LOCK_FILE"

# 시작 로그
log_message "Proxmox Ceph Squid 저장소 미러링 시작"

# CephFS 마운트 확인
if ! mountpoint -q "/mnt/cephfs"; then
    log_message "CephFS가 마운트되지 않았습니다. 마운트를 시도합니다."
    mkdir -p "/mnt/cephfs"
    ceph-fuse "/mnt/cephfs" || {
        log_message "CephFS 마운트 실패"
        rm -f "$LOCK_FILE"
        exit 1
    }
fi

# 미러 디렉토리 생성
mkdir -p "$MIRROR_LOCAL_PATH"

# wget을 사용한 미러링
log_message "wget을 사용하여 Ceph Squid 저장소 미러링 중..."

cd "$MIRROR_LOCAL_PATH"

# 기존 파일 백업 (선택사항)
if [ -d "backup" ]; then
    rm -rf "backup"
fi
mkdir -p "backup"

# wget 옵션 설정 (속도 우선)
WGET_OPTS="--mirror --no-parent --timeout=30 --tries=3 --retry-connrefused --user-agent='Mozilla/5.0 (compatible; ProxmoxMirror/1.0)' --progress=bar --show-progress --append-output=$LOG_FILE"

# 미러링 시작 시간 기록
START_TIME=$(date +%s)
log_message "미러링 시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
log_message "미러링 대상 URL: $MIRROR_BASE_URL"
log_message "미러링 대상 경로: $MIRROR_LOCAL_PATH"

# 미러링 실행 (백그라운드에서 실행하고 진행률 모니터링)
log_message "미러링 명령어 실행: wget $WGET_OPTS $MIRROR_BASE_URL"
echo ">> 미러링이 시작되었습니다. 진행 상황을 모니터링합니다..."
echo ">> 10초마다 진행률이 업데이트됩니다."
echo ">> Ctrl+C를 눌러도 미러링은 백그라운드에서 계속 실행됩니다."
echo ""

# 백그라운드에서 wget 실행
wget $WGET_OPTS "$MIRROR_BASE_URL" > /tmp/wget_output.log 2>&1 &
WGET_PID=$!

# 진행률 모니터링
echo ">> 미러링 PID: $WGET_PID"
echo ">> 실시간 진행률 확인 중..."
echo "=========================================="

# 30초마다 진행률 체크
while kill -0 $WGET_PID 2>/dev/null; do
    CURRENT_TIME=$(date '+%H:%M:%S')
    
    # 현재 다운로드된 파일 수
    CURRENT_FILES=$(find . -type f 2>/dev/null | wc -l)
    CURRENT_SIZE=$(du -sh . 2>/dev/null | cut -f1)
    
    echo "[$CURRENT_TIME] 진행 중... 파일: $CURRENT_FILES개, 크기: $CURRENT_SIZE"
    
    # wget 로그에서 최근 진행률 확인
    if [ -f /tmp/wget_output.log ]; then
        RECENT_PROGRESS=$(tail -5 /tmp/wget_output.log | grep -E "%|Saving to" | tail -1)
        if [ ! -z "$RECENT_PROGRESS" ]; then
            echo "  최근 진행: $RECENT_PROGRESS"
        fi
        
        # 다운로드 속도 확인
        SPEED_INFO=$(tail -10 /tmp/wget_output.log | grep -E "MB/s|KB/s" | tail -1)
        if [ ! -z "$SPEED_INFO" ]; then
            echo "  다운로드 속도: $SPEED_INFO"
        fi
    fi
    
    sleep 10
done

# wget 프로세스 완료 대기
wait $WGET_PID
WGET_EXIT_CODE=$?

# 미러링 완료 시간 기록
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [ $WGET_EXIT_CODE -eq 0 ]; then
    log_message "Ceph Squid 저장소 미러링 완료"
    log_message "미러링 완료 시간: $(date '+%Y-%m-%d %H:%M:%S')"
    log_message "총 소요 시간: ${DURATION}초 ($(echo "scale=1; $DURATION / 60" | bc)분)"
    
    # 다운로드된 파일 통계
    TOTAL_FILES=$(find . -type f | wc -l)
    TOTAL_SIZE=$(du -sh . | cut -f1)
    log_message "다운로드된 파일 수: $TOTAL_FILES"
    log_message "총 다운로드 크기: $TOTAL_SIZE"
    
    # 파일 권한 설정
    log_message "파일 권한 설정 중..."
    find . -type f -exec chmod 644 {} \;
    find . -type d -exec chmod 755 {} \;
    log_message "파일 권한 설정 완료"
    
    # nginx 재시작
    log_message "nginx 재시작 중..."
    systemctl reload nginx
    log_message "nginx 재시작 완료"
    
    echo ">> 미러링이 성공적으로 완료되었습니다!"
    echo ">> 다운로드된 파일: $TOTAL_FILES개"
    echo ">> 총 크기: $TOTAL_SIZE"
    echo ">> 소요 시간: ${DURATION}초"
else
    # 미러링 실패 시 시간 기록
    log_message "미러링 실패 - 소요 시간: ${DURATION}초"
    log_message "실패 시간: $(date '+%Y-%m-%d %H:%M:%S')"
    log_message "wget 종료 코드: $WGET_EXIT_CODE"
    
    echo ">> 미러링이 실패했습니다. 로그를 확인하세요:"
    echo ">> 로그 파일: $LOG_FILE"
    echo ">> wget 출력: /tmp/wget_output.log"
    
    rm -f "$LOCK_FILE"
    exit 1
fi

# 임시 파일 정리
rm -f /tmp/wget_output.log
log_message "Proxmox Ceph Squid 저장소 미러링 완료"
EOF

# 스크립트 실행 권한 부여
chmod +x /usr/local/bin/proxmox-mirror-sync.sh

#=========================================================================
# 4. nginx 설정 생성
#=========================================================================
echo -e "\n[단계 4/6] nginx 설정 생성 중..."

cat > "$NGINX_CONFIG_PATH" << EOF
server {
    listen $NGINX_PORT;
    server_name _;
    
    # 로그 설정
    access_log /var/log/nginx/proxmox-mirror-access.log;
    error_log /var/log/nginx/proxmox-mirror-error.log;
    
    # 루트 디렉토리
    root $MIRROR_LOCAL_PATH;
    index index.html index.htm;
    
    # 디렉토리 인덱싱 활성화
    autoindex on;
    autoindex_exact_size off;
    autoindex_localtime on;
    
    # 캐시 설정
    location ~* \.(deb|gpg|asc)$ {
        expires 1d;
        add_header Cache-Control "public, immutable";
    }
    
    # 압축 설정
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    # 보안 헤더
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # 기본 위치 설정
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # 특별한 파일 타입 처리
    location ~* \.(deb)$ {
        add_header Content-Type application/vnd.debian.binary-package;
    }
    
    location ~* \.(gpg|asc)$ {
        add_header Content-Type application/pgp-signature;
    }
}
EOF

# nginx 설정 활성화
ln -sf "$NGINX_CONFIG_PATH" "$NGINX_ENABLED_PATH"

# nginx 설정 테스트
echo ">> nginx 설정 테스트 중..."
nginx -t

# nginx 재시작
echo ">> nginx 재시작 중..."
systemctl restart nginx
systemctl enable nginx

#=========================================================================
# 5. cronjob 설정
#=========================================================================
echo -e "\n[단계 5/6] cronjob 설정 중..."

# cronjob 파일 생성
cat > "$CRON_JOB_FILE" << EOF
# Proxmox 저장소 미러링 - 매일 새벽 2시에 실행
0 2 * * * root /usr/local/bin/proxmox-mirror-sync.sh

# 로그 로테이션 - 매주 일요일 새벽 3시에 실행
0 3 * * 0 root find /var/log -name "proxmox-mirror.log*" -mtime +7 -delete
EOF

# cron 서비스 재시작
systemctl restart cron

#=========================================================================
# 6. 초기 미러링 실행
#=========================================================================
echo -e "\n[단계 6/6] 초기 미러링 실행 중..."

# 초기 미러링 실행
echo ">> 초기 미러링을 시작합니다. 이 과정은 시간이 오래 걸릴 수 있습니다..."
echo ">> 미러링 진행 상황을 확인하려면 다음 명령어를 사용하세요:"
echo "   tail -f $LOG_FILE"
echo ">> 또는 새 터미널에서 다음 명령어로 실시간 모니터링:"
echo "   watch -n 5 'ls -la $MIRROR_LOCAL_PATH | wc -l && du -sh $MIRROR_LOCAL_PATH'"
echo ""

/usr/local/bin/proxmox-mirror-sync.sh

#=========================================================================
# 7. 설정 완료 및 정보 표시
#=========================================================================
echo -e "\n[완료] Proxmox Ceph Squid 저장소 미러링 설정이 완료되었습니다."
echo ""
echo "===== 설정 정보 ====="
echo "미러 저장소 경로: $MIRROR_LOCAL_PATH"
echo "소스 URL: $MIRROR_BASE_URL"
echo "nginx 포트: $NGINX_PORT"
echo "웹 접속 URL: http://$(hostname -I | awk '{print $1}'):$NGINX_PORT"
echo "로그 파일: $LOG_FILE"
echo ""
echo "===== 관리 명령어 ====="
echo "수동 미러링 실행: /usr/local/bin/proxmox-mirror-sync.sh"
echo "nginx 상태 확인: systemctl status nginx"
echo "로그 확인: tail -f $LOG_FILE"
echo "실시간 진행률 확인: watch -n 5 'ls -la $MIRROR_LOCAL_PATH | wc -l && du -sh $MIRROR_LOCAL_PATH'"
echo "cronjob 확인: crontab -l"
echo ""
echo "===== 자동화 설정 ====="
echo "매일 새벽 2시에 자동 미러링이 실행됩니다."
echo "cronjob 파일: $CRON_JOB_FILE"
echo ""
echo "===== 주의사항 ====="
echo "1. Ceph Squid 저장소는 Ceph 18.2.x 버전의 패키지를 포함합니다."
echo "2. 초기 미러링은 시간이 오래 걸릴 수 있습니다."
echo "3. 디스크 공간을 충분히 확보하세요."
echo "4. 네트워크 대역폭을 고려하여 미러링 시간을 조정하세요." 