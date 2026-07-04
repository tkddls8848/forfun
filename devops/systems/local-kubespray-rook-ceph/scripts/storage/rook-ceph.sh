#!/usr/bin/env bash
set -euo pipefail

ROOK_VERSION="${ROOK_VERSION:-v1.20.0}"
ROOK_HOME="${ROOK_HOME:-$HOME/rook}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[rook] kubectl is not available. Run kubespray.sh first." >&2
  exit 1
fi

if [[ ! -d "$ROOK_HOME/.git" ]]; then
  echo "[rook] cloning $ROOK_VERSION"
  git clone --single-branch --branch "$ROOK_VERSION" https://github.com/rook/rook.git "$ROOK_HOME"
else
  echo "[rook] updating existing checkout: $ROOK_HOME"
  git -C "$ROOK_HOME" fetch --tags origin
  git -C "$ROOK_HOME" checkout "$ROOK_VERSION"
fi

cd "$ROOK_HOME/deploy/examples"

echo "[rook] installing operator resources"
kubectl apply -f crds.yaml
kubectl wait --for=condition=Established --timeout=180s crd/cephclusters.ceph.rook.io
kubectl apply -f common.yaml -f csi-operator.yaml -f operator.yaml
kubectl -n rook-ceph rollout status deploy/rook-ceph-operator --timeout=5m

echo "[rook] creating Ceph cluster"
kubectl apply -f cluster.yaml -f toolbox.yaml
kubectl -n rook-ceph wait --for=condition=Ready cephcluster/rook-ceph --timeout=30m
kubectl -n rook-ceph rollout status deploy/rook-ceph-tools --timeout=5m

echo "[rook] waiting for Ceph health"
health=""
for _ in {1..60}; do
  health="$(kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health 2>/dev/null || true)"
  if [[ "$health" == "HEALTH_OK" ]]; then
    break
  fi
  sleep 10
done
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
if [[ "$health" != "HEALTH_OK" ]]; then
  echo "[rook] Ceph did not reach HEALTH_OK: $health" >&2
  exit 1
fi

echo "[rook] installing RBD storage class"
kubectl apply -f csi/rbd/storageclass.yaml
kubectl get storageclass rook-ceph-block >/dev/null

echo "[rook] exposing dashboard through MetalLB"
kubectl apply -f dashboard-loadbalancer.yaml
