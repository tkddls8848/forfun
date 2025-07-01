#!/bin/bash
#=========================================================================
# Ceph 모니터링 설정 스크립트 (Podman 버전)
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

echo "=========================================="
echo "Ceph 모니터링 설정 시작"
echo "=========================================="
echo "현재 호스트: $(hostname)"
echo "=========================================="

#=========================================================================
# 1. Ceph Dashboard 활성화
#=========================================================================
echo -e "\n[단계 1/3] Ceph Dashboard 활성화 중..."

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
# 2. Prometheus 모듈 활성화
#=========================================================================
echo -e "\n[단계 2/3] Prometheus 모듈 활성화 중..."

# Prometheus 모듈 활성화
echo ">> Prometheus 모듈 활성화 중..."
ceph mgr module enable prometheus

# Prometheus 포트 설정
echo ">> Prometheus 포트 설정 중..."
ceph config set mgr mgr/prometheus/server_port 9283

#=========================================================================
# 3. 모니터링 서비스 상태 확인
#=========================================================================
echo -e "\n[단계 3/3] 모니터링 서비스 상태 확인 중..."

# MGR 모듈 상태 확인
echo ">> MGR 모듈 상태 확인:"
ceph mgr module ls | grep -E "(dashboard|prometheus)"

# Dashboard 상태 확인
echo ">> Dashboard 상태 확인:"
ceph mgr services

# Prometheus 엔드포인트 확인
echo ">> Prometheus 엔드포인트 확인:"
ceph mgr services | grep prometheus

echo -e "\n[완료] Ceph 모니터링 설정이 완료되었습니다."
echo "=========================================="
echo "===== 모니터링 접속 정보 ====="
echo "Ceph Dashboard: http://$(hostname -I | awk '{print $1}'):8080"
echo "  사용자: admin"
echo "  비밀번호: admin"
echo ""
echo "Prometheus Metrics: http://$(hostname -I | awk '{print $1}'):9283/metrics"
echo ""
echo "===== 유용한 명령어 ====="
echo "클러스터 상태: ceph -s"
echo "헬스 상세: ceph health detail"
echo "OSD 상태: ceph osd status"
echo "풀 상태: ceph df"
echo "서비스 상태: ceph orch ls"
echo ""
echo "===== 대시보드 접속 방법 ====="
echo "1. 브라우저에서 http://$(hostname -I | awk '{print $1}'):8080 접속"
echo "2. 사용자명: admin, 비밀번호: admin 입력"
echo "3. 클러스터 상태, OSD, 풀 등의 정보 확인 가능"
echo "=========================================="