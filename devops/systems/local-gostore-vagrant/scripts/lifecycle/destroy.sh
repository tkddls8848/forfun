#!/bin/bash
#
# 랩 정리. VM 과 이 랩이 만든 데이터 디스크를 지운다.
#
# 디스크 파일은 VirtualBox 가 VM 삭제 시 자동으로 지우지 않는 경우가 있어
# 남으면 다음 vagrant up 이 "이미 포맷됨"으로 실패한다. 그래서 명시적으로 지운다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DISK_DIR="$HOME/vagrant_disks/gostore-lab"

cd "$LAB_ROOT"
echo "[step=destroy][target=vm] VM 삭제"
vagrant destroy -f

if [ -d "$DISK_DIR" ]; then
  echo "[step=destroy][target=disk] 데이터 디스크 삭제: $DISK_DIR"
  rm -rf "$DISK_DIR"
fi

echo "[step=destroy][target=local] 완료 (dist/ 의 바이너리는 유지됩니다)"
