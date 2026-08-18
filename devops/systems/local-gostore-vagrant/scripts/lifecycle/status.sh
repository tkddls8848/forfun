#!/bin/bash
#
# 랩 상태 요약. VM 상태와 각 노드의 저장소 상태를 함께 보여준다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INVENTORY="$LAB_ROOT/inventory/inventory.ini"

CONTROL_PORT="$(sed -n 's/^control_port=\(.*\)$/\1/p' "$INVENTORY" | head -1 | tr -d '[:space:]')"

echo "=== VM ==="
(cd "$LAB_ROOT" && vagrant status)

echo
echo "=== 노드 ==="
if curl -sf "http://localhost:${CONTROL_PORT}/api/nodes" 2>/dev/null; then
  echo
else
  echo "컨트롤러에 접속할 수 없습니다 (http://localhost:${CONTROL_PORT})."
  echo "랩이 떠 있는지 확인하세요: vagrant up"
fi
