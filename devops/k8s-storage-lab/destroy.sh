#!/bin/bash
set -e

cd "$(dirname "$0")/opentofu"
tofu destroy -auto-approve
cd ..
rm -f scripts/.env
echo "✅ 전체 삭제 완료"
