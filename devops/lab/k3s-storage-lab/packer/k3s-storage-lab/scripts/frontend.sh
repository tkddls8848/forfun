#!/bin/bash
set -e

K3S_VERSION="v1.31.6+k3s1"

# k3s 바이너리만 다운로드 (서비스 등록 X)
# INSTALL_K3S_SKIP_START=true: 설치 후 서비스 시작 안 함
# INSTALL_K3S_SKIP_ENABLE=true: systemd enable 안 함
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  INSTALL_K3S_SKIP_START=true \
  INSTALL_K3S_SKIP_ENABLE=true \
  sh -

echo "k3s 바이너리 설치 완료 (서비스 등록 제외)"
k3s --version
