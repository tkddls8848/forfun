#!/bin/bash
#
# 에이전트 배포. 이 스크립트에는 패키지 설치가 한 줄도 없다.
#
#   $1 = 노드 이름   $2 = 저장소 경로   $3 = 백엔드 라벨   $4 = 포트
#   환경변수 GOSTORE_TOKEN = 컨트롤러와 공유하는 시크릿
#
# 대조군인 local-ceph-vagrant/apps/block-store-app/scripts/run-agent.sh 는
# 같은 자리에서 다음을 한다:
#   curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
#   apt-get install -y nodejs
#   npm install --omit=dev
# 즉 노드마다 인터넷·apt·npm 레지스트리 세 곳에 의존한다. 여기서는 정적
# 바이너리 하나를 복사하는 것이 배포의 전부이므로 그 의존이 모두 사라진다.
set -euo pipefail

NODE_NAME="${1:?노드 이름 인자가 필요합니다}"
STORE_DIR="${2:?저장소 경로 인자가 필요합니다}"
BACKEND="${3:?백엔드 라벨 인자가 필요합니다}"
PORT="${4:?포트 인자가 필요합니다}"
: "${GOSTORE_TOKEN:?GOSTORE_TOKEN 환경변수가 필요합니다}"

SRC="/vagrant-dist/gostore-linux-$(dpkg --print-architecture)"
BIN="/usr/local/bin/gostore"
ENV_FILE="/etc/gostore/agent.env"

log() { echo "[step=agent][target=${NODE_NAME}] $*"; }
fail() { echo "[step=agent][target=${NODE_NAME}][failed] reason=$*" >&2; exit 1; }

START_NS=$(date +%s%N)

[ -f "$SRC" ] || fail "바이너리가 없습니다: $SRC (호스트에서 'bash scripts/build.sh' 실행)"

log "바이너리 설치: $(stat -c%s "$SRC") bytes"
install -m 0755 "$SRC" "$BIN"

# 전용 시스템 계정. root 로 돌릴 이유가 없고, 저장소 소유권을 이 계정에 준다.
id -u gostore >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin gostore
chown gostore:gostore "$STORE_DIR"

# 토큰은 유닛 파일이 아니라 별도 환경 파일에 둔다. 유닛 파일은 world-readable
# 이므로 여기에 시크릿을 적으면 노드의 모든 사용자가 읽는다.
install -d -m 0750 -o root -g gostore /etc/gostore
umask 077
cat > "$ENV_FILE" <<ENVEOF
GOSTORE_TOKEN=${GOSTORE_TOKEN}
ENVEOF
chown root:gostore "$ENV_FILE"
chmod 0640 "$ENV_FILE"

cat > /etc/systemd/system/gostore-agent.service <<UNITEOF
[Unit]
Description=gostore agent (${NODE_NAME}, ${BACKEND})
Documentation=https://github.com/tkddls8848/forfun
# 저장소가 마운트된 뒤에 뜬다. 마운트 전에 뜨면 루트 디스크에 쓰기 시작한다.
RequiresMountsFor=${STORE_DIR}
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=gostore
Group=gostore
EnvironmentFile=${ENV_FILE}
ExecStart=${BIN} agent \\
  --node ${NODE_NAME} \\
  --addr :${PORT} \\
  --store-dir ${STORE_DIR} \\
  --backend ${BACKEND}
Restart=on-failure
RestartSec=2

# 정적 바이너리라 실행에 필요한 것이 저장소 경로뿐이다. 나머지는 다 잠근다.
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
ReadWritePaths=${STORE_DIR}

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable --now gostore-agent.service >/dev/null

# 기동 확인. /health 는 토큰 없이 열려 있으므로 여기서 바로 쓸 수 있다.
for _ in $(seq 1 50); do
  if curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    ELAPSED_MS=$(( ($(date +%s%N) - START_NS) / 1000000 ))
    log "기동 완료 (${ELAPSED_MS}ms, 설치한 패키지 0개)"
    curl -s "http://127.0.0.1:${PORT}/health"; echo
    exit 0
  fi
  sleep 0.2
done

journalctl -u gostore-agent.service --no-pager -n 30 >&2 || true
fail "에이전트가 기동하지 않았습니다"
