#!/bin/bash
# k3s-storage-lab 전체 구성 자동화 — Stage 1 → 2 → 3 순차 실행
# 각 스테이지를 개별 실행하려면:
#   bash start_1_infra_k3s.sh
#   bash start_2_ceph.sh
#   bash start_3_beegfs.sh
#
# 롤백 (역순):
#   bash rollback_3_beegfs.sh
#   bash rollback_2_ceph.sh
#   bash rollback_1_infra.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

bash "$SCRIPT_DIR/start_1_infra_k3s.sh"
bash "$SCRIPT_DIR/start_2_ceph.sh"
bash "$SCRIPT_DIR/start_3_beegfs.sh"
