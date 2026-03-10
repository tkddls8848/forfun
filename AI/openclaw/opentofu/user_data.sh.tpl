#!/usr/bin/env bash
# OpenClaw 자동 설치 스크립트 (Ubuntu 22.04 LTS)
set -euo pipefail
exec > /var/log/openclaw-setup.log 2>&1

echo "==> [1/5] 시스템 업데이트"
apt-get update -y
apt-get upgrade -y
apt-get install -y curl git unzip ca-certificates gnupg

echo "==> [2/5] Node.js 22 설치"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
node --version

echo "==> [3/5] Docker 설치"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
usermod -aG docker ubuntu

echo "==> [4/5] OpenClaw 설치"
# ubuntu 유저로 설치
sudo -u ubuntu bash << 'OPENCLAW_INSTALL'
  set -euo pipefail
  cd /home/ubuntu

  # pnpm 공식 설치 스크립트 사용
  export PNPM_HOME="/home/ubuntu/.local/share/pnpm"
  curl -fsSL https://get.pnpm.io/install.sh | env PNPM_HOME="$PNPM_HOME" sh -
  export PATH="$PNPM_HOME:$PATH"

  # OpenClaw 글로벌 설치
  pnpm add -g openclaw@latest
  pnpm approve-builds -g

  # PATH 영구 등록
  echo 'export PNPM_HOME="/home/ubuntu/.local/share/pnpm"' >> /home/ubuntu/.bashrc
  echo 'export PATH="$PNPM_HOME:$PATH"' >> /home/ubuntu/.bashrc

  # OpenClaw 초기화 (daemon 모드)
  openclaw onboard --install-daemon --non-interactive || true

OPENCLAW_INSTALL

echo "==> [5/5] 완료"
echo "OpenClaw 설치 완료: $(date)"
echo "UI 접속: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):18789"
echo "토큰 확인: cat /home/ubuntu/.openclaw/.env | grep TOKEN"
