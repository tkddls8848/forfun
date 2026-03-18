#!/usr/bin/env bash
# OpenClaw 자동 설치 스크립트 (Ubuntu 24.04 LTS)
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

  # PATH 영구 등록 (onboard 이전에 먼저 설정)
  grep -qxF 'export PNPM_HOME="/home/ubuntu/.local/share/pnpm"' /home/ubuntu/.bashrc || \
    echo 'export PNPM_HOME="/home/ubuntu/.local/share/pnpm"' >> /home/ubuntu/.bashrc
  grep -qxF 'export PATH="$PNPM_HOME:$PATH"' /home/ubuntu/.bashrc || \
    echo 'export PATH="$PNPM_HOME:$PATH"' >> /home/ubuntu/.bashrc

  # OpenClaw 글로벌 설치 (native 모듈 빌드 포함: 'a' = select all)
  pnpm add -g openclaw@latest
  printf 'a\n' | pnpm approve-builds -g || true

  # OpenClaw 초기화 (daemon 모드) — 실패 시 로그 출력
  if openclaw onboard --install-daemon --non-interactive --accept-risk; then
    echo "openclaw onboard 완료"
  else
    echo "WARNING: openclaw onboard 실패 (exit $?)"
    which openclaw || echo "openclaw binary 없음: $PATH"
  fi

OPENCLAW_INSTALL

echo "==> [5/5] AWS Bedrock 연동 설정"
# IAM Instance Profile(Role)로 자격증명 자동 주입 — 별도 키 불필요
# .openclaw/.env 에 Bedrock 리전 설정 추가
ENV_FILE="/home/ubuntu/.openclaw/.env"
if [[ -f "$ENV_FILE" ]]; then
  # 기존 항목 제거 후 추가 (중복 방지)
  grep -v '^BEDROCK_AWS_REGION\|^AWS_REGION' "$ENV_FILE" > /tmp/.env.tmp || true
  cat >> /tmp/.env.tmp << 'ENVEOF'

# AWS Bedrock 연동 (EC2 IAM Role로 자동 인증)
BEDROCK_AWS_REGION=ap-northeast-2
AWS_REGION=ap-northeast-2
ENVEOF
  mv /tmp/.env.tmp "$ENV_FILE"
  chown ubuntu:ubuntu "$ENV_FILE"
  echo "Bedrock 환경 변수 설정 완료"

  # OpenClaw 데몬 재시작
  if systemctl is-active --quiet openclaw 2>/dev/null; then
    systemctl restart openclaw
    echo "OpenClaw 서비스 재시작 완료"
  fi
else
  echo "WARNING: $ENV_FILE 파일이 없습니다. openclaw onboard 실패 가능성 있음."
fi

echo "==> 설치 완료: $(date)"
# IMDSv2 토큰으로 퍼블릭 IP 조회
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4)
echo "UI 접속: http://$PUBLIC_IP:18789"
echo "토큰 확인: grep TOKEN /home/ubuntu/.openclaw/.env"
