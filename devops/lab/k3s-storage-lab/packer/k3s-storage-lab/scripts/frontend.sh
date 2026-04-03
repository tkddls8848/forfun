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

# Docker CE 설치 — storage-test-app 이미지 빌드 및 k3s containerd 임포트에 사용
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io
# ubuntu 유저가 sudo 없이 docker 사용 가능하도록
usermod -aG docker ubuntu
echo "Docker 설치 완료: $(docker --version)"
