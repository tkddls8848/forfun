#!/bin/bash
#
# 컨트롤러 배포. 에이전트와 같은 바이너리를 같은 방식으로 설치한다.
#
#   $1 = 노드 목록 "name=host:port:backend,..."   $2 = 포트
#   환경변수 GOSTORE_TOKEN = 에이전트와 공유하는 시크릿
#
# 웹 UI 는 //go:embed 로 바이너리 안에 있다. 정적 파일을 따로 옮기지 않고,
# nginx 같은 웹서버도 두지 않는다.
set -euo pipefail

NODES_SPEC="${1:?노드 목록 인자가 필요합니다}"
PORT="${2:?포트 인자가 필요합니다}"
: "${GOSTORE_TOKEN:?GOSTORE_TOKEN 환경변수가 필요합니다}"

SRC="/vagrant-dist/gostore-linux-$(dpkg --print-architecture)"
BIN="/usr/local/bin/gostore"
ENV_FILE="/etc/gostore/control.env"

log() { echo "[step=control][target=controller] $*"; }
fail() { echo "[step=control][target=controller][failed] reason=$*" >&2; exit 1; }

[ -f "$SRC" ] || fail "바이너리가 없습니다: $SRC (호스트에서 'bash scripts/build.sh' 실행)"

log "바이너리 설치: $(stat -c%s "$SRC") bytes"
install -m 0755 "$SRC" "$BIN"

id -u gostore >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin gostore

install -d -m 0750 -o root -g gostore /etc/gostore
umask 077
cat > "$ENV_FILE" <<ENVEOF
GOSTORE_TOKEN=${GOSTORE_TOKEN}
GOSTORE_NODES=${NODES_SPEC}
ENVEOF
chown root:gostore "$ENV_FILE"
chmod 0640 "$ENV_FILE"

cat > /etc/systemd/system/gostore-control.service <<UNITEOF
[Unit]
Description=gostore controller
Documentation=https://github.com/tkddls8848/forfun
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=gostore
Group=gostore
EnvironmentFile=${ENV_FILE}
ExecStart=${BIN} control --addr :${PORT}
Restart=on-failure
RestartSec=2

# 컨트롤러는 디스크에 쓰지 않는다 — 파일은 전부 에이전트로 중계된다.
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable --now gostore-control.service >/dev/null

for _ in $(seq 1 50); do
  if curl -sf "http://127.0.0.1:${PORT}/api/nodes" >/dev/null 2>&1; then
    log "기동 완료 (설치한 패키지 0개)"
    exit 0
  fi
  sleep 0.2
done

journalctl -u gostore-control.service --no-pager -n 30 >&2 || true
fail "컨트롤러가 기동하지 않았습니다"
