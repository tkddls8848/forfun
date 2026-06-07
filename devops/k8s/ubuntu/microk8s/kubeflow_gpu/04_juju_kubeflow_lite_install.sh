#!/usr/bin/env bash
set -euo pipefail

JUJU_CHANNEL="${JUJU_CHANNEL:-3.6/stable}"
KUBEFLOW_CHANNEL="${KUBEFLOW_CHANNEL:-1.10/stable}"
RESET_JUJU="${RESET_JUJU:-false}"
KUBEFLOW_PORT="${KUBEFLOW_PORT:-1234}"

if [[ "$RESET_JUJU" == "true" ]]; then
  sudo snap remove juju --purge 2>/dev/null || true
  rm -rf "$HOME/.local/share/juju" "$HOME/.juju" "$HOME/.config/juju" "$HOME/.cache/juju" 2>/dev/null || true
fi

if ! snap list juju >/dev/null 2>&1; then
  sudo snap install juju --channel="$JUJU_CHANNEL"
fi

export JUJU_DATA="$HOME/.local/share/juju"
mkdir -p "$JUJU_DATA"

microk8s config | juju add-k8s my-k8s --client
juju bootstrap my-k8s
juju add-model kubeflow
juju deploy kubeflow-lite --trust --channel="$KUBEFLOW_CHANNEL"

juju config dex-auth static-username=admin
juju config dex-auth static-password=admin

sudo sysctl fs.inotify.max_user_instances=1280
sudo sysctl fs.inotify.max_user_watches=655360

timeout 1800 bash -c 'until juju status kubeflow 2>/dev/null | grep -q "active"; do sleep 60; done'

nohup microk8s kubectl port-forward -n kubeflow svc/istio-ingressgateway-workload "${KUBEFLOW_PORT}:80" \
  >/tmp/kubeflow-port-forward.log 2>&1 &
echo $! >/tmp/kubeflow-port-forward.pid

if microk8s kubectl get nodes -o json | jq -e '.items[].status.allocatable | select(."nvidia.com/gpu" != null)' >/dev/null 2>&1; then
  echo "GPU is available for Kubeflow workloads."
else
  echo "GPU was not detected by Kubernetes; GPU workloads may not schedule." >&2
fi

echo "Kubeflow dashboard: http://localhost:${KUBEFLOW_PORT}"
echo "Username: admin"
echo "Password: admin"
