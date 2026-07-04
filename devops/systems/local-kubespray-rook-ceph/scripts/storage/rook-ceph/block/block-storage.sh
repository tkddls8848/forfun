#!/usr/bin/env bash
set -euo pipefail

## ceph blocksystem
ROOK_HOME="${ROOK_HOME:-$HOME/rook}"
cd "$ROOK_HOME/deploy/examples"
kubectl apply -f csi/rbd/storageclass.yaml
kubectl get storageclass rook-ceph-block >/dev/null

## test ceph block storage by wordpress app
if [[ "${RUN_DEMO_APP:-false}" == "true" ]]; then
  kubectl apply -f mysql.yaml
  kubectl apply -f wordpress.yaml
fi
