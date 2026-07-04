#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# .env?ì„œ IP ë¯¸ë¦¬ ?˜ì§‘ (?? œ ?? - ë°°ì—´ ?¬í•¨
NODE_IPS=()
if [ -f "$LAB_ROOT/scripts/system/.env" ]; then
  source "$LAB_ROOT/scripts/system/.env"
  NODE_IPS=($M1_PUB "${WORKER_PUBS[@]}")
fi

# AWS ?¸í”„???? œ
cd "$LAB_ROOT/opentofu"
tofu destroy -auto-approve
cd "$LAB_ROOT"

# ë¡œì»¬ ?¤ì • ?•ë¦¬
rm -f scripts/system/.env
rm -f ~/.kube/config-k8s-storage-lab

# SSH known_hosts?ì„œ ?¸ë“œ IP ?œê±° (?¬ìƒ????host key ì¶©ëŒ ë°©ì?)
for ip in "${NODE_IPS[@]}"; do
  ssh-keygen -R "$ip" 2>/dev/null || true
done

echo "???„ì²´ ?? œ ?„ë£Œ (?¸í”„??+ ë¡œì»¬ kubeconfig + known_hosts)"
