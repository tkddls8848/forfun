#!/bin/bash
#=========================================================================
# Ceph 모니터링 설정 스크립트 (Podman 버전)
# - Ceph Dashboard 활성화
# - Prometheus 서버 설치 및 설정
# - Grafana 설치 및 설정
# - 모니터링 통합 설정
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

echo "=========================================="
echo "Ceph 모니터링 설정 시작"
echo "=========================================="
echo "현재 호스트: $(hostname)"
echo "=========================================="

#=========================================================================
# 1. 사전 요구사항 확인 및 설치
#=========================================================================
echo -e "\n[단계 1/5] 사전 요구사항 확인 및 설치 중..."

# Podman 설치 확인
if ! command -v podman &> /dev/null; then
    echo ">> Podman이 설치되어 있지 않습니다. 설치 중..."
    apt update
    apt install -y podman
fi

# net-tools 설치 확인 (포트 확인용)
if ! command -v netstat &> /dev/null; then
    echo ">> net-tools가 설치되어 있지 않습니다. 설치 중..."
    apt update
    apt install -y net-tools
fi

# curl 설치 확인
if ! command -v curl &> /dev/null; then
    echo ">> curl이 설치되어 있지 않습니다. 설치 중..."
    apt update
    apt install -y curl
fi

#=========================================================================
# 2. Prometheus 모듈 활성화 및 서버 설치
#=========================================================================
echo -e "\n[단계 2/5] Prometheus 모듈 활성화 및 서버 설치 중..."

# Prometheus 모듈 활성화
echo ">> Prometheus 모듈 활성화 중..."
ceph mgr module enable prometheus

# Prometheus 포트 설정
echo ">> Prometheus 포트 설정 중..."
ceph config set mgr mgr/prometheus/server_port 9283

# 기존 Prometheus 컨테이너가 있다면 제거
if podman ps -a | grep -q prometheus; then
    echo ">> 기존 Prometheus 컨테이너 제거 중..."
    podman stop prometheus 2>/dev/null || true
    podman rm prometheus 2>/dev/null || true
    echo ">> 기존 Prometheus 컨테이너 제거 완료"
fi

# 9090번 포트 사용 여부 확인
if netstat -tlnp | grep -q ":9090 "; then
    echo ">> 9090번 포트가 사용 중입니다. 9091번 포트로 변경합니다."
    PROMETHEUS_PORT=9091
else
    echo ">> 9090번 포트 사용 가능합니다."
    PROMETHEUS_PORT=9090
fi

# Prometheus 설정 파일 생성
echo ">> Prometheus 설정 파일 생성 중..."
mkdir -p /opt/prometheus
cat > /opt/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'ceph'
    static_configs:
      - targets: ['localhost:9283']
    metrics_path: '/metrics'
    scrape_interval: 15s
EOF

# Prometheus 컨테이너 실행
echo ">> Prometheus 컨테이너 실행 중..."
podman run -d \
    --name prometheus \
    --restart=unless-stopped \
    -p ${PROMETHEUS_PORT}:9090 \
    -v /opt/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
    prom/prometheus:latest \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/prometheus \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.console.templates=/etc/prometheus/consoles

# Prometheus 시작 대기
echo ">> Prometheus 시작 대기 중..."
sleep 10

#=========================================================================
# 3. Ceph Dashboard 활성화
#=========================================================================
echo -e "\n[단계 3/5] Ceph Dashboard 활성화 중..."

# Ceph Dashboard 활성화
echo ">> Ceph Dashboard 활성화 중..."
ceph mgr module enable dashboard

# Dashboard SSL 비활성화 (테스트 환경용)
echo ">> Dashboard SSL 비활성화 중..."
ceph config set mgr mgr/dashboard/ssl false

# Dashboard 포트 설정
echo ">> Dashboard 포트 설정 중..."
ceph config set mgr mgr/dashboard/server_port 8080

# Dashboard 접근 허용
echo ">> Dashboard 접근 허용 설정 중..."
echo "admin" > /tmp/admin_password
ceph dashboard set-login-credentials admin -i /tmp/admin_password
rm -f /tmp/admin_password

#=========================================================================
# 4. Grafana 설치 및 설정
#=========================================================================
echo -e "\n[단계 4/5] Grafana 설치 및 설정 중..."

# 기존 Grafana 컨테이너가 있다면 제거
if podman ps -a | grep -q grafana; then
    echo ">> 기존 Grafana 컨테이너 제거 중..."
    podman stop grafana 2>/dev/null || true
    podman rm grafana 2>/dev/null || true
    echo ">> 기존 Grafana 컨테이너 제거 완료"
fi

# 3000번 포트 사용 여부 확인 (기존 컨테이너 제거 후)
if netstat -tlnp | grep -q ":3000 "; then
    echo ">> 3000번 포트가 사용 중입니다. 3001번 포트로 변경합니다."
    GRAFANA_PORT=3001
else
    echo ">> 3000번 포트 사용 가능합니다."
    GRAFANA_PORT=3000
fi

# Grafana 컨테이너 실행
echo ">> Grafana 컨테이너 실행 중..."
podman run -d \
    --name grafana \
    --restart=unless-stopped \
    -p ${GRAFANA_PORT}:3000 \
    -e GF_SECURITY_ADMIN_PASSWORD=admin \
    -e GF_SECURITY_ADMIN_USER=admin \
    -e GF_USERS_ALLOW_SIGN_UP=false \
    grafana/grafana:latest

# Grafana가 완전히 시작될 때까지 대기 (더 긴 대기 시간)
echo ">> Grafana 시작 대기 중..."
sleep 15

# Grafana 서비스 준비 상태 확인
echo ">> Grafana 서비스 준비 상태 확인 중..."
MAX_RETRIES=10
RETRY_INTERVAL=5
count=0

while [ $count -lt $MAX_RETRIES ]; do
    if curl -s http://localhost:${GRAFANA_PORT}/api/health | grep -q "ok"; then
        echo ">> Grafana 서비스 준비 완료"
        break
    fi
    echo "   Grafana 준비 대기 중... ($((count+1))/$MAX_RETRIES)"
    sleep $RETRY_INTERVAL
    count=$((count+1))
done

if [ $count -eq $MAX_RETRIES ]; then
    echo ">> Grafana 서비스 준비 시간 초과"
    exit 1
fi

# Grafana에 Prometheus 데이터소스 추가
echo ">> Prometheus 데이터소스 추가 중..."
curl -X POST \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"Prometheus\",
        \"type\": \"prometheus\",
        \"url\": \"http://localhost:${PROMETHEUS_PORT}\",
        \"access\": \"proxy\",
        \"isDefault\": true
    }" \
    http://admin:admin@localhost:${GRAFANA_PORT}/api/datasources

# Ceph Dashboard에 Grafana URL 등록
echo ">> Ceph Dashboard에 Grafana URL 등록 중..."
GRAFANA_URL="http://$(hostname -I | awk '{print $1}'):${GRAFANA_PORT}"
ceph dashboard set-grafana-api-url "${GRAFANA_URL}"

#=========================================================================
# 5. 모니터링 서비스 상태 확인
#=========================================================================
echo -e "\n[단계 5/5] 모니터링 서비스 상태 확인 중..."

# MGR 모듈 상태 확인
echo ">> MGR 모듈 상태 확인:"
ceph mgr module ls | grep -E "(dashboard|prometheus)"

# Dashboard 상태 확인
echo ">> Dashboard 상태 확인:"
ceph mgr services

# Prometheus 엔드포인트 확인
echo ">> Prometheus 엔드포인트 확인:"
ceph mgr services | grep prometheus

# 컨테이너 상태 확인
echo ">> 컨테이너 상태 확인:"
echo "-- Prometheus 컨테이너:"
podman ps | grep prometheus || echo "   Prometheus 컨테이너가 실행되지 않음"
echo "-- Grafana 컨테이너:"
podman ps | grep grafana || echo "   Grafana 컨테이너가 실행되지 않음"

echo -e "\n[완료] Ceph 모니터링 설정이 완료되었습니다."
echo "=========================================="
echo "===== 모니터링 접속 정보 ====="
echo "Ceph Dashboard: http://$(hostname -I | awk '{print $1}'):8080"
echo "  사용자: admin"
echo "  비밀번호: admin"
echo ""
echo "Prometheus: http://$(hostname -I | awk '{print $1}'):${PROMETHEUS_PORT}"
echo "  - 타겟: http://$(hostname -I | awk '{print $1}'):9283/metrics"
echo ""
echo "Grafana: http://$(hostname -I | awk '{print $1}'):${GRAFANA_PORT}"
echo "  사용자: admin"
echo "  비밀번호: admin"
echo ""
echo "Ceph Prometheus Metrics: http://$(hostname -I | awk '{print $1}'):9283/metrics"
echo ""
echo "===== 유용한 명령어 ====="
echo "클러스터 상태: ceph -s"
echo "헬스 상세: ceph health detail"
echo "OSD 상태: ceph osd status"
echo "풀 상태: ceph df"
echo "서비스 상태: ceph orch ls"
echo "컨테이너 상태: podman ps"
echo ""
echo "===== 대시보드 접속 방법 ====="
echo "1. Ceph Dashboard: http://[외부IP]:8080"
echo "2. Grafana: http://[외부IP]:${GRAFANA_PORT}"
echo "3. Prometheus: http://[외부IP]:${PROMETHEUS_PORT}"
echo "=========================================="