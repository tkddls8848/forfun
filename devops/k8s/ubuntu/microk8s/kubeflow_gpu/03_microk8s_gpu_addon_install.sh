#!/usr/bin/env bash
set -euo pipefail

MICROK8S_CHANNEL="${MICROK8S_CHANNEL:-1.32/stable}"
METALLB_RANGE="${METALLB_RANGE:-172.30.1.240-172.30.1.250}"
RESET_MICROK8S="${RESET_MICROK8S:-false}"

if ! systemctl is-active --quiet snapd; then
  sudo systemctl enable snapd
  sudo systemctl start snapd
fi

if [[ "$RESET_MICROK8S" == "true" ]]; then
  sudo snap remove microk8s --purge 2>/dev/null || true
  sudo rm -rf /var/snap/microk8s 2>/dev/null || true
fi

sudo swapoff -a
sudo sed -e '/swap/s/^/#/' -i /etc/fstab

if ! snap list microk8s >/dev/null 2>&1; then
  sudo snap install microk8s --classic --channel="$MICROK8S_CHANNEL"
fi

mkdir -p "$HOME/.kube"
sudo usermod -a -G microk8s "$USER"
sudo chown -f -R "$USER" "$HOME/.kube"

sudo microk8s start
sudo microk8s status --wait-ready

sudo microk8s enable dns
sudo microk8s enable hostpath-storage
sudo microk8s enable rbac

if [[ ! "$METALLB_RANGE" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid METALLB_RANGE: $METALLB_RANGE" >&2
  exit 1
fi
sudo microk8s enable "metallb:$METALLB_RANGE"

if ! sudo microk8s enable nvidia; then
  sleep 30
  sudo microk8s enable nvidia --validate=false
fi

TIMEOUT=900
COUNTER=0
while [[ "$COUNTER" -lt "$TIMEOUT" ]]; do
  if sudo microk8s kubectl get namespace gpu-operator-resources >/dev/null 2>&1; then
    if sudo microk8s kubectl get pods -n gpu-operator-resources -l app=nvidia-operator-validator --no-headers 2>/dev/null | grep -q "Running"; then
      break
    fi
  elif sudo microk8s kubectl get pods -n kube-system -l app=nvidia-device-plugin-daemonset --no-headers 2>/dev/null | grep -q "Running"; then
    break
  fi
  sleep 5
  COUNTER=$((COUNTER + 5))
done

if [[ "$COUNTER" -ge "$TIMEOUT" ]]; then
  echo "GPU addon did not become ready within ${TIMEOUT}s." >&2
  exit 1
fi

sudo microk8s kubectl get nodes -o wide
sudo microk8s kubectl describe nodes | grep -i nvidia || true
