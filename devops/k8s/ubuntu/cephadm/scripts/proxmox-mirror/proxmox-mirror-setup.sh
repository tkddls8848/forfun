#!/bin/bash
#=========================================================================
# Proxmox Ceph Squid 저장소 미러링 설정 스크립트 (wget 최적화 - 수정됨)
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

# 설정 변수
export MIRROR_BASE_URL="http://download.proxmox.com/debian/ceph-squid/dists/bookworm/no-subscription/binary-amd64/"
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
echo ">> nginx, wget, rsync, bc 설치 중..."
apt-get install -y nginx wget rsync curl bc

#=========================================================================
# 3. 수정된 미러링 스크립트 생성
#=========================================================================
echo -e "\n[단계 3/6] 수정된 미러링 스크립트 생성 중..."

cat > /usr/local/bin/proxmox-mirror-sync.sh << 'EOF'
#!/bin/bash
# Proxmox Ceph Squid 저장소 미러링 스크립트 (wget 최적화 - 수정됨)

set -e

# 설정 변수
MIRROR_BASE_URL="http://download.proxmox.com/debian/ceph-squid/dists/bookworm/no-subscription/binary-amd64/"
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

# 정리 함수
cleanup() {
    rm -f "$LOCK_FILE"
    rm -f /tmp/wget_output.log
    rm -f /tmp/wget_mirror.pid
    rm -f /tmp/wget_start_marker
    log_message "미러링 프로세스 정리 완료"
}

# 시그널 트랩 설정
trap cleanup EXIT INT TERM

# 시작 로그
log_message "Proxmox Ceph Squid 저장소 미러링 시작"

# CephFS 마운트 확인
if ! mountpoint -q "/mnt/cephfs"; then
    log_message "CephFS가 마운트되지 않았습니다. 마운트를 시도합니다."
    mkdir -p "/mnt/cephfs"
    ceph-fuse "/mnt/cephfs" || {
        log_message "CephFS 마운트 실패"
        exit 1
    }
fi

# 미러 디렉토리 생성
mkdir -p "$MIRROR_LOCAL_PATH"

# wget을 사용한 최적화된 미러링
log_message "wget을 사용하여 Ceph Squid 저장소 미러링 중..."

cd "$MIRROR_LOCAL_PATH"

# wget 옵션 설정 (단순화 - 다운로드 문제 해결)
WGET_OPTS="--recursive --level=inf --no-parent --timestamping --continue --timeout=60 --tries=3 --retry-connrefused --no-check-certificate --limit-rate=0 --progress=dot:mega --verbose"

# 미러링 시작 시간 기록
START_TIME=$(date +%s)
log_message "미러링 시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
log_message "미러링 대상 URL: $MIRROR_BASE_URL"
log_message "미러링 대상 경로: $MIRROR_LOCAL_PATH"

# 미러링 실행 (수정됨 - 올바른 백그라운드 실행)
log_message "최적화된 wget 명령어 실행"
echo ">> 단순화된 고속 미러링이 시작되었습니다..."
echo ">> 60초마다 진행률이 업데이트됩니다."
echo ">> Ctrl+C를 눌러도 안전하게 종료됩니다."
echo ""

# 시작 마커 생성 (새로 다운로드되는 파일 추적용)
touch /tmp/wget_start_marker

# wget 백그라운드 실행 (수정됨)
wget $WGET_OPTS "$MIRROR_BASE_URL" > /tmp/wget_output.log 2>&1 &
WGET_PID=$!

# PID 파일에 기록 및 확인
echo $WGET_PID > /tmp/wget_mirror.pid
log_message "wget 프로세스 시작됨 (PID: $WGET_PID)"

# PID 유효성 확인
if ! kill -0 $WGET_PID 2>/dev/null; then
    log_message "ERROR: wget 프로세스 시작 실패"
    exit 1
fi

# 진행률 모니터링 (수정됨)
echo ">> 미러링 PID: $WGET_PID"
echo ">> 실시간 진행률 확인 중..."
echo "=========================================="

# 초기 대기 (wget이 완전히 시작될 때까지)
sleep 5

# 60초마다 진행률 체크
MONITORING_COUNT=0
while kill -0 $WGET_PID 2>/dev/null; do
    CURRENT_TIME=$(date '+%H:%M:%S')
    MONITORING_COUNT=$((MONITORING_COUNT + 1))
    
    # 현재 다운로드된 파일 수 (더 정확한 카운팅)
    CURRENT_FILES=$(find . -type f -newer /tmp/wget_start_marker 2>/dev/null | wc -l)
    ALL_FILES=$(find . -type f 2>/dev/null | wc -l)
    CURRENT_SIZE=$(du -sh . 2>/dev/null | cut -f1 || echo "계산중...")
    
    echo "[$CURRENT_TIME] 모니터링 #$MONITORING_COUNT - 신규파일: $CURRENT_FILES개, 전체파일: $ALL_FILES개, 총크기: $CURRENT_SIZE"
    
    # wget 로그에서 최근 활동 확인
    if [ -f /tmp/wget_output.log ]; then
        # 파일 크기 확인 (로그가 생성되고 있는지)
        LOG_SIZE=$(wc -c < /tmp/wget_output.log 2>/dev/null || echo "0")
        echo "  로그 크기: ${LOG_SIZE} bytes"
        
        # 최근 wget 활동 상세 분석
        RECENT_LINES=$(tail -10 /tmp/wget_output.log 2>/dev/null)
        if [ ! -z "$RECENT_LINES" ]; then
            echo "  === 최근 wget 활동 ==="
            echo "$RECENT_LINES" | while read line; do
                if [[ "$line" == *"Resolving"* ]]; then
                    echo "  🔍 DNS 해석: $(echo "$line" | cut -c1-60)..."
                elif [[ "$line" == *"Connecting"* ]]; then
                    echo "  🔗 연결중: $(echo "$line" | cut -c1-60)..."
                elif [[ "$line" == *"HTTP request sent"* ]]; then
                    echo "  📤 HTTP 요청: $(echo "$line" | cut -c1-60)..."
                elif [[ "$line" == *"saved"* ]]; then
                    echo "  ✅ 저장됨: $(echo "$line" | cut -c1-60)..."
                elif [[ "$line" == *"Length:"* ]]; then
                    echo "  📏 파일크기: $(echo "$line" | cut -c1-60)..."
                elif [[ "$line" == *"%"* ]]; then
                    echo "  📊 진행률: $(echo "$line" | cut -c1-60)..."
                elif [[ "$line" == *"ERROR"* ]] || [[ "$line" == *"failed"* ]]; then
                    echo "  ❌ 에러: $(echo "$line" | cut -c1-60)..."
                fi
            done
            echo "  ======================"
        else
            echo "  ⚠️  wget 로그가 비어있습니다."
        fi
        
        # 마지막 성공적인 다운로드 확인
        LAST_SAVED=$(grep "saved" /tmp/wget_output.log 2>/dev/null | tail -1)
        if [ ! -z "$LAST_SAVED" ]; then
            echo "  마지막 다운로드: $(echo "$LAST_SAVED" | cut -c1-80)..."
        else
            echo "  ⚠️  아직 다운로드된 파일이 없습니다."
        fi
    else
        echo "  ⚠️  wget 로그 파일이 생성되지 않았습니다."
    fi
    
    # 60초 대기
    echo "  다음 체크까지 60초 대기..."
    echo ""
    sleep 60
done

# wget 프로세스 완료 확인
log_message "wget 프로세스 종료 감지, 완료 대기 중..."
wait $WGET_PID
WGET_EXIT_CODE=$?

# 미러링 완료 시간 기록
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 최종 로그 분석
if [ -f /tmp/wget_output.log ]; then
    FINAL_LOG_SIZE=$(wc -c < /tmp/wget_output.log)
    log_message "최종 wget 로그 크기: $FINAL_LOG_SIZE bytes"
    
    # 마지막 몇 줄 로그 기록
    echo "=== 최종 wget 로그 (마지막 10줄) ===" >> "$LOG_FILE"
    tail -10 /tmp/wget_output.log >> "$LOG_FILE" 2>/dev/null || echo "로그 읽기 실패" >> "$LOG_FILE"
    echo "================================" >> "$LOG_FILE"
fi

if [ $WGET_EXIT_CODE -eq 0 ]; then
    log_message "Ceph Squid 저장소 미러링 성공적으로 완료"
    log_message "미러링 완료 시간: $(date '+%Y-%m-%d %H:%M:%S')"
    log_message "총 소요 시간: ${DURATION}초 ($(echo "scale=1; $DURATION / 60" | bc)분)"
    
    # 다운로드된 파일 통계
    TOTAL_DEBS=$(find . -name "*.deb" 2>/dev/null | wc -l)
    TOTAL_FILES=$(find . -type f 2>/dev/null | wc -l)
    TOTAL_SIZE=$(du -sh . 2>/dev/null | cut -f1 || echo "알수없음")
    log_message "다운로드된 패키지 파일: $TOTAL_DEBS개"
    log_message "총 파일 수: $TOTAL_FILES"
    log_message "총 다운로드 크기: $TOTAL_SIZE"
    
    # 파일 권한 설정
    log_message "파일 권한 설정 중..."
    find . -type f -exec chmod 644 {} \; 2>/dev/null &
    find . -type d -exec chmod 755 {} \; 2>/dev/null &
    wait
    log_message "파일 권한 설정 완료"
    
    # nginx 재시작
    log_message "nginx 재시작 중..."
    systemctl reload nginx
    log_message "nginx 재시작 완료"
    
    echo ">> 미러링이 성공적으로 완료되었습니다!"
    echo ">> 다운로드된 패키지: $TOTAL_DEBS개"
    echo ">> 총 파일: $TOTAL_FILES개"
    echo ">> 총 크기: $TOTAL_SIZE"
    echo ">> 소요 시간: ${DURATION}초 ($(echo "scale=1; $DURATION / 60" | bc)분)"
    
    # 통계 출력
    if [ "$TOTAL_DEBS" -gt 0 ] && [ "$DURATION" -gt 0 ]; then
        AVG_SPEED=$(echo "scale=2; $TOTAL_DEBS / ($DURATION / 60)" | bc 2>/dev/null || echo "계산불가")
        echo ">> 평균 다운로드 속도: ${AVG_SPEED} 파일/분"
    fi
    
    # 성공 상태로 종료
    exit 0
else
    # 미러링 실패 또는 부분 완료 처리
    log_message "wget 종료 코드: $WGET_EXIT_CODE"
    log_message "미러링 소요 시간: ${DURATION}초"
    
    # 다운로드된 파일이 있는지 확인
    TOTAL_DEBS=$(find . -name "*.deb" 2>/dev/null | wc -l)
    TOTAL_FILES=$(find . -type f 2>/dev/null | wc -l)
    
    if [ "$TOTAL_DEBS" -gt 0 ]; then
        log_message "부분적 미러링 완료 - 다운로드된 패키지: $TOTAL_DEBS개"
        echo ">> 미러링이 부분적으로 완료되었습니다."
        echo ">> 다운로드된 패키지: $TOTAL_DEBS개"
        echo ">> 총 파일: $TOTAL_FILES개"
        echo ">> 자세한 로그: $LOG_FILE"
        echo ">> wget 출력: /tmp/wget_output.log"
        
        # nginx 재시작
        systemctl reload nginx
        log_message "nginx 재시작 완료"
        
        # 부분 성공으로 종료
        exit 0
    else
        log_message "미러링 완전 실패 - 다운로드된 파일 없음"
        echo ">> 미러링이 실패했습니다."
        echo ">> 로그 파일: $LOG_FILE"
        echo ">> wget 출력: /tmp/wget_output.log"
        exit 1
    fi
fi
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
# Proxmox 저장소 미러링 - 매일 새벽 1시에 실행
0 1 * * * root /usr/local/bin/proxmox-mirror-sync.sh

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
echo ">> 수정된 최적화 미러링을 시작합니다..."
echo ">> 미러링 진행 상황을 확인하려면 다음 명령어를 사용하세요:"
echo "   tail -f $LOG_FILE"
echo ">> 또는 새 터미널에서 다음 명령어로 실시간 모니터링:"
echo "   watch -n 10 'find $MIRROR_LOCAL_PATH -name \"*.deb\" | wc -l && du -sh $MIRROR_LOCAL_PATH'"
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
echo "미러링 중단: kill \$(cat /tmp/wget_mirror.pid 2>/dev/null) 2>/dev/null"
echo "nginx 상태 확인: systemctl status nginx"
echo "로그 확인: tail -f $LOG_FILE"
echo "패키지 파일 수 확인: find $MIRROR_LOCAL_PATH -name '*.deb' | wc -l"
echo "실시간 진행률 확인: watch -n 10 'find $MIRROR_LOCAL_PATH -name \"*.deb\" | wc -l && du -sh $MIRROR_LOCAL_PATH'"
echo "cronjob 확인: crontab -l"
echo ""
echo "===== 자동화 설정 ====="
echo "매일 새벽 2시에 자동 미러링이 실행됩니다."
echo "cronjob 파일: $CRON_JOB_FILE"
echo ""
echo "===== 문제 진단 명령어 ====="
echo "wget 로그 실시간 확인: tail -f /tmp/wget_output.log"
echo "URL 접근 테스트: curl -I $MIRROR_BASE_URL"
echo "wget 테스트: wget --spider --recursive --level=1 $MIRROR_BASE_URL"
echo "현재 다운로드 상태: ls -la $MIRROR_LOCAL_PATH"
echo "신규 파일 확인: find $MIRROR_LOCAL_PATH -newer /tmp/wget_start_marker 2>/dev/null"
echo ""
echo "===== 수정 사항 ====="
echo "1. 제한적인 accept/reject 필터 제거로 다운로드 문제 해결"
echo "2. cut-dirs, no-host-directories 옵션 제거"
echo "3. 더 상세한 wget 활동 모니터링 추가"
echo "4. 신규 파일과 전체 파일 구분 카운팅"
echo "5. wget 로그 실시간 분석 기능 강화"