#!/usr/bin/env bash
set -euo pipefail

K3S_VERSION="${K3S_VERSION:-v1.32.3+k3s1}"
K3AI_INSTALLER_URL="${K3AI_INSTALLER_URL:-}"

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -s -

if [[ -n "$K3AI_INSTALLER_URL" ]]; then
  curl -sfL "$K3AI_INSTALLER_URL" | sh -s -- --pipelines
else
  echo "Skipping K3ai. Set K3AI_INSTALLER_URL to a pinned installer URL to enable it."
fi
