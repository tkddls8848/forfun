#!/bin/bash
# k3s-storage-lab ?ÑÏ≤¥ Íµ¨ÏÑ± ?êÎèô????Stage 1 ??2 ??3 ?úÏ∞® ?§Ìñâ
# Í∞??§ÌÖå?¥Ï?Î•?Í∞úÎ≥Ñ ?§Ìñâ?òÎ†§Î©?
#   bash scripts/lifecycle/start_1_infra_k3s.sh
#   bash scripts/lifecycle/start_2_ceph.sh
#   bash scripts/lifecycle/start_3_beegfs.sh
#
# Î°§Î∞± (??àú):
#   bash scripts/lifecycle/rollback_3_beegfs.sh
#   bash scripts/lifecycle/rollback_2_ceph.sh
#   bash scripts/lifecycle/rollback_1_infra.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

bash "$SCRIPT_DIR/start_1_infra_k3s.sh"
bash "$SCRIPT_DIR/start_2_ceph.sh"
bash "$SCRIPT_DIR/start_3_beegfs.sh"
