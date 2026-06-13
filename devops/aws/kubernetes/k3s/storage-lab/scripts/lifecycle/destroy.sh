#!/bin/bash
# k3s-storage-lab ?„ì²´ ?? œ
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$LAB_ROOT/opentofu"
tofu destroy -auto-approve

echo "???„ì²´ ?? œ ?„ë£Œ"
