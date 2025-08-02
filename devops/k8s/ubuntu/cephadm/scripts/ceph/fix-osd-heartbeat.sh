#!/bin/bash
#=========================================================================
# OSD Heartbeat 문제 해결 스크립트
# - Slow OSD heartbeats 경고 해결
# - 성능 최적화 설정 적용
# - 네트워크 설정 조정
#=========================================================================

set -e

echo "=========================================="
echo "OSD Heartbeat 문제 해결 스크립트 시작"
echo "=========================================="

#=========================================================================
# 1. 현재 상태 확인
#=========================================================================
echo -e "\n[단계 1/5] 현재 클러스터 상태 확인 중..."

echo ">> 클러스터 상태:"
ceph -s

echo ">> OSD 상태:"
ceph osd status

echo ">> 네트워크 지연 확인:"
ceph osd ping

#=========================================================================
# 2. OSD Heartbeat 설정 조정
#=========================================================================
echo -e "\n[단계 2/5] OSD Heartbeat 설정 조정 중..."

echo ">> OSD heartbeat 타임아웃 설정 중..."
ceph config set osd osd_heartbeat_grace 20
ceph config set osd osd_heartbeat_interval 6

echo ">> 네트워크 타임아웃 설정 중..."
ceph config set global ms_tcp_read_timeout 900
ceph config set global ms_tcp_write_timeout 900

echo ">> 네트워크 버퍼 설정 중..."
ceph config set global ms_dispatch_throttle_bytes 104857600

#=========================================================================
# 3. OSD 성능 최적화
#=========================================================================
echo -e "\n[단계 3/5] OSD 성능 최적화 중..."

echo ">> 백필 및 복구 설정 최적화 중..."
ceph config set osd osd_max_backfills 1
ceph config set osd osd_recovery_max_active 1
ceph config set osd osd_recovery_max_single_start 1

echo ">> 캐시 크기 최적화 중..."
ceph config set osd bluestore_cache_size_ssd 1073741824
ceph config set osd bluestore_cache_size_hdd 268435456

echo ">> 글로벌 복구 설정 중..."
ceph config set global osd_recovery_max_chunk 1048576

#=========================================================================
# 4. 시스템 리소스 최적화
#=========================================================================
echo -e "\n[단계 4/5] 시스템 리소스 최적화 중..."

echo ">> 시스템 파라미터 조정 중..."
# 네트워크 버퍼 크기 증가
echo 'net.core.rmem_max = 134217728' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 134217728' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_rmem = 4096 87380 134217728' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_wmem = 4096 65536 134217728' >> /etc/sysctl.conf

# sysctl 설정 적용
sysctl -p

echo ">> I/O 스케줄러 설정 중..."
# SSD용 noop 스케줄러 설정
for disk in $(lsblk -dn -o NAME | grep -E "sd[b-z]"); do
    echo noop > /sys/block/$disk/queue/scheduler 2>/dev/null || true
done

#=========================================================================
# 5. OSD 서비스 재시작 및 상태 확인
#=========================================================================
echo -e "\n[단계 5/5] OSD 서비스 재시작 및 상태 확인 중..."

echo ">> OSD 서비스 재시작 중..."
ceph orch restart osd

echo ">> 재시작 대기 중..."
sleep 30

echo ">> 최종 상태 확인 중..."
echo ">> 클러스터 상태:"
ceph -s

echo ">> OSD 상태:"
ceph osd status

echo ">> 네트워크 지연 재확인:"
ceph osd ping

echo -e "\n[완료] OSD Heartbeat 문제 해결 스크립트가 완료되었습니다."
echo "=========================================="
echo "적용된 설정:"
echo "  - OSD heartbeat grace: 20초"
echo "  - OSD heartbeat interval: 6초"
echo "  - TCP read/write timeout: 900초"
echo "  - 네트워크 버퍼: 100MB"
echo "  - 백필/복구 최적화"
echo "  - 캐시 크기 최적화"
echo "=========================================="
echo "추가 권장사항:"
echo "  1. VirtualBox VM 메모리를 4GB 이상으로 증가"
echo "  2. CPU 코어 수를 4개 이상으로 증가"
echo "  3. 네트워크 어댑터를 82540EM으로 변경"
echo "  4. 호스트 시스템 리소스 모니터링"
echo "==========================================" 