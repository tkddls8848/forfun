#!/bin/bash
# k3s-storage-lab 전체 삭제
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR/opentofu"
tofu destroy -auto-approve

echo "✅ 전체 삭제 완료"
