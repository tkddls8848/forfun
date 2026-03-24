#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# .env에서 IP 미리 수집 (삭제 전) - 배열 포함
NODE_IPS=()
if [ -f "$SCRIPT_DIR/scripts/.env" ]; then
  source "$SCRIPT_DIR/scripts/.env"
  NODE_IPS=($M1_PUB "${WORKER_PUBS[@]}" $N1_PUB $N2_PUB)
fi

# AWS 인프라 삭제
cd "$SCRIPT_DIR/opentofu"
tofu destroy -auto-approve
cd "$SCRIPT_DIR"

# 로컬 설정 정리
rm -f scripts/.env
rm -f ~/.kube/config-k8s-storage-lab

# SSH known_hosts에서 노드 IP 제거 (재생성 시 host key 충돌 방지)
for ip in "${NODE_IPS[@]}"; do
  ssh-keygen -R "$ip" 2>/dev/null || true
done

echo "✅ 전체 삭제 완료 (인프라 + 로컬 kubeconfig + known_hosts)"
