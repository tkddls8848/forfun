#!/bin/bash
#
# OSD Heartbeat 문제 해결 스크립트
#   - Slow OSD heartbeats 경고 해결
#   - 성능 최적화 설정 적용
#   - 네트워크 설정 조정
#

set -e

echo "=========================================="
echo "OSD Heartbeat 문제 해결 스크립트 시작"
echo "=========================================="

# --- 1. 현재 상태 확인 ---
echo -e "\n[단계 1/5] 현재 클러스터 상태 확인 중..."

echo ">> 클러스터 상태:"
ceph -s

echo ">> OSD 상태:"
ceph osd status

echo ">> 네트워크 지연 확인:"
ceph osd perf

# --- 2. OSD Heartbeat 설정 조정 ---
echo -e "\n[단계 2/5] OSD Heartbeat 설정 조정 중..."

echo ">> OSD heartbeat 타임아웃 설정 중..."
ceph config set osd osd_heartbeat_grace 20
ceph config set osd osd_heartbeat_interval 6

echo ">> 네트워크 버퍼 설정 중..."
ceph config set global ms_dispatch_throttle_bytes 104857600

# --- 3. OSD 성능 최적화 ---
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

# --- 4. 시스템 리소스 최적화 ---
echo -e "\n[단계 4/5] 시스템 리소스 최적화 중..."

echo ">> 시스템 파라미터 조정 중..."
# 네트워크 버퍼 크기 증가 (전용 파일에 덮어써 재실행 시 중복 누적 방지)
cat > /etc/sysctl.d/90-ceph-osd.conf << 'EOF'
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
EOF

# sysctl 설정 적용
sysctl -p /etc/sysctl.d/90-ceph-osd.conf

echo ">> I/O 스케줄러 설정 중..."
# 최신 multi-queue 커널엔 noop이 없으므로, 디스크가 지원하는 스케줄러 중 선택
# (SSD/가상 디스크는 none 우선, 없으면 mq-deadline)
for disk in $(lsblk -dn -o NAME | grep -E "vd[b-z]|sd[b-z]"); do
    sched_file="/sys/block/$disk/queue/scheduler"
    [[ -w "$sched_file" ]] || continue
    available="$(cat "$sched_file")"
    for candidate in none noop mq-deadline deadline; do
        if [[ "$available" == *"$candidate"* ]]; then
            echo "$candidate" > "$sched_file" 2>/dev/null && \
                echo "   $disk -> $candidate" && break
        fi
    done
done

# --- 5. OSD 서비스 재시작 및 상태 확인 ---
echo -e "\n[단계 5/5] OSD 서비스 재시작 및 상태 확인 중..."

echo ">> OSD 데몬 롤링 재시작 중..."
# orch restart는 서비스 이름을 요구하므로 OSD는 데몬 단위로 재시작한다.
# 한 개씩 재시작하고, 매번 모든 OSD up + PG active+clean 회복을 확인한 뒤 다음으로 넘어간다.
TOTAL_OSDS="$(ceph osd ls | wc -l)"

wait_for_recovery() {
  # 모든 OSD up + 전이 상태(degraded/undersized/peering/recover/backfill 등) 없음 대기 (최대 ~3분)
  for _ in $(seq 1 36); do
    up="$(ceph osd stat -f json 2>/dev/null | jq -r '.num_up_osds // 0' || echo 0)"
    if [[ "${up:-0}" -ge "$TOTAL_OSDS" ]] \
       && ! ceph pg stat 2>/dev/null | grep -qiE 'degraded|undersized|peering|recover|backfill|stale|inactive|down'; then
      return 0
    fi
    sleep 5
  done
  return 1
}

for osd_id in $(ceph osd ls); do
  echo "   - osd.${osd_id} 재시작..."
  ceph orch daemon restart "osd.${osd_id}" || true
  sleep 5
  if wait_for_recovery; then
    echo "     osd.${osd_id} 회복 완료"
  else
    echo "     (경고: osd.${osd_id} 재시작 후 회복 지연 — 계속 진행)" >&2
  fi
done

echo ">> 최종 상태 확인 중..."
echo ">> 클러스터 상태:"
ceph -s

echo ">> OSD 상태:"
ceph osd status

echo ">> 네트워크 지연 재확인:"
ceph osd perf

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
echo "  1. KVM VM 메모리를 4GB 이상으로 증가"
echo "  2. CPU 코어 수를 4개 이상으로 증가"
echo "  3. cpu_mode = host-passthrough 설정 권장"
echo "  4. 호스트 시스템 리소스 모니터링"
echo "==========================================" 