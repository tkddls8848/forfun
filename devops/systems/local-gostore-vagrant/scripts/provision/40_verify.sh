#!/bin/bash
#
# 랩 구성 검증. vagrant up 마지막에 자동 실행된다.
#   $1 = 컨트롤러 IP   $2 = 컨트롤러 포트
#
# 각 노드가 (a) 응답하고 (b) 의도한 파일시스템에 실제로 올라가 있는지 확인한다.
# (b)를 빼면 마운트가 빠진 노드가 루트 디스크에 쓰면서도 정상으로 보인다.
set -euo pipefail

CONTROL_IP="${1:?컨트롤러 IP 인자가 필요합니다}"
PORT="${2:?포트 인자가 필요합니다}"
URL="http://127.0.0.1:${PORT}"

log() { echo "[step=verify][target=lab] $*"; }

log "노드 상태 조회"
NODES_JSON="$(curl -sf "${URL}/api/nodes")" || {
  echo "[step=verify][target=lab][failed] reason=컨트롤러에 접속할 수 없습니다: $URL" >&2
  exit 1
}

# 게스트에 파이썬을 요구하지 않으려고 awk 로 읽는다.
# 레코드 구분자를 "name":" 로 두면 노드 하나가 레코드 하나가 된다. 중첩된
# usage 객체가 같은 레코드 안에 들어오므로 fs_type 까지 한 줄로 뽑을 수 있다.
read -r TOTAL OK <<<"$(awk 'BEGIN{RS="\"name\":\""; t=0; o=0}
  NR>1 { t++; if (/"ok":true/) o++ }
  END { print t, o }' <<<"$NODES_JSON")"

echo
# 한글은 표시 폭이 2 이므로 printf 의 %-Ns 정렬이 어긋난다. 헤더는 직접 맞춘다.
echo "  NODE               BACKEND(선언)  FS(실제)     STATE"
echo "  ---------------------------------------------------------------"
awk 'BEGIN{RS="\"name\":\""; FS="\n"}
  NR>1 {
    name = substr($0, 1, index($0, "\"") - 1)
    backend = "-"; fs = "-"; state = "FAIL"
    if (match($0, /"backend":"[^"]*"/))
      backend = substr($0, RSTART+11, RLENGTH-12)
    if (match($0, /"fs_type":"[^"]*"/))
      fs = substr($0, RSTART+11, RLENGTH-12)
    if ($0 ~ /"ok":true/) state = "OK"
    if (backend == "") backend = "-"
    printf "  %-18s %-14s %-12s %s\n", name, backend, fs, state
  }' <<<"$NODES_JSON"
echo

if [ "$OK" -ne "$TOTAL" ]; then
  echo "[step=verify][target=lab][failed] reason=${TOTAL}개 중 ${OK}개만 정상입니다" >&2
  echo "$NODES_JSON" >&2
  exit 1
fi
log "노드 ${OK}/${TOTAL} 정상"

log "스모크 벤치마크 (2초, 동시성 8)"
gostore bench --control "127.0.0.1:${PORT}" --mode mixed --concurrency 8 --seconds 2 --payload-kb 16

cat <<BANNER

  랩 준비 완료.

    UI            http://localhost:${PORT}   (호스트 브라우저)
                  http://${CONTROL_IP}:${PORT}
    벤치마크      vagrant ssh ${HOSTNAME} -c 'gostore bench --mode write --fsync --seconds 20'
                  또는 호스트에서: bash scripts/lifecycle/bench.sh --mode write --fsync

BANNER
