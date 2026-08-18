#!/bin/bash
#
# 호스트에서 랩 벤치마크를 돌린다. 인자는 gostore bench 로 그대로 넘어간다.
#
#   bash scripts/lifecycle/bench.sh                              # 기본 (mixed, 10초)
#   bash scripts/lifecycle/bench.sh --mode write --fsync --seconds 20
#   bash scripts/lifecycle/bench.sh --matrix                     # 조합 전체를 순차 실행
#
# 호스트에 Go 가 있으면 dist/ 의 바이너리를 그대로 쓰고, 없으면 컨트롤 VM 안에서
# 실행한다. 어느 쪽이든 같은 바이너리다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INVENTORY="$LAB_ROOT/inventory/inventory.ini"

inv_var() {
  local key="$1"
  sed -n "s/^${key}=\(.*\)$/\1/p" "$INVENTORY" | head -1 | tr -d '[:space:]'
}

CONTROL_PORT="$(inv_var control_port)"
CONTROL_IP="$(awk '/^\[control\]/{f=1;next} /^\[/{f=0} f && /ansible_host=/{
  for(i=1;i<=NF;i++) if($i ~ /^ansible_host=/){split($i,a,"="); print a[2]; exit}}' "$INVENTORY")"

[ -n "$CONTROL_PORT" ] || { echo "[bench][failed] reason=인벤토리에서 control_port 를 읽지 못했습니다" >&2; exit 1; }
[ -n "$CONTROL_IP" ]   || { echo "[bench][failed] reason=인벤토리에서 컨트롤 노드 IP 를 읽지 못했습니다" >&2; exit 1; }

BIN="$LAB_ROOT/dist/gostore-linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"

# 호스트에서 직접 실행할 수 있는지 확인한다. 리눅스가 아니거나 바이너리가 없으면
# 컨트롤 VM 안에서 돌린다.
run_bench() {
  if [ "$(uname -s)" = "Linux" ] && [ -x "$BIN" ]; then
    "$BIN" bench --control "${CONTROL_IP}:${CONTROL_PORT}" "$@"
  else
    vagrant ssh gostore-control -c \
      "gostore bench --control 127.0.0.1:${CONTROL_PORT} $*" 2>/dev/null
  fi
}

if [ "${1:-}" = "--matrix" ]; then
  # 백엔드 비교에서 실제로 궁금한 축만 돌린다: 캐시 여부(fsync)와 동시성.
  echo "=== 벤치마크 매트릭스 ==="
  for mode in read write mixed; do
    for fsync in "" "--fsync"; do
      # 읽기 워크로드에 fsync 는 의미가 없다.
      [ "$mode" = "read" ] && [ -n "$fsync" ] && continue
      echo
      echo "--- mode=$mode ${fsync:-(fsync off)} ---"
      run_bench --mode "$mode" --concurrency 32 --seconds 10 --payload-kb 64 $fsync
    done
  done
  exit 0
fi

if [ $# -eq 0 ]; then
  run_bench --mode mixed --concurrency 16 --seconds 10 --payload-kb 64
else
  run_bench "$@"
fi
