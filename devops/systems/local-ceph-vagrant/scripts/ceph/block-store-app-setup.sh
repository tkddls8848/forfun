#!/bin/bash
#
# 블록 스토어 앱 배포 (master에서 실행, privileged).
# cephadm-setup.sh 이후 단계 — 클러스터/cephadm SSH 키/worker 인증이 끝난 상태 전제.
#
#   - master: 중앙앱(central) systemd 서비스 (UI :3333)
#   - 각 worker: rbd 클라이언트 배포 → RBD 마운트 → 에이전트(agent) systemd 서비스 (:4000)
#
# 노드 간 작업은 ansible(인벤토리)로 수행한다. 앱 코드는 Vagrant synced_folder로
# master의 $APP_SRC 에 올라와 있어야 한다.
#
# args: <network_prefix> <worker_length>
# env : AGENT_TOKEN(공유 시크릿), APP_SRC(앱 소스 경로), RBD_POOL

set -euo pipefail

NETWORK_PREFIX="${1:?network prefix is required}"
WORKER_LENGTH="${2:?worker length is required}"
AGENT_TOKEN="${AGENT_TOKEN:-change-me-token}"
APP_SRC="${APP_SRC:-/opt/ceph-block-store-src}"
RBD_POOL="${RBD_POOL:-rbd-pool}"

APP_DST="/opt/ceph-block-store"
STORE_DIR="/srv/rbd-store"
AGENT_PORT=4000
CENTRAL_PORT=3333
MASTER_IP="${NETWORK_PREFIX}.10"
ANSIBLE_DIR="/tmp/block-store-ansible"

echo "[block-store] 배포 시작 (workers=$WORKER_LENGTH, pool=$RBD_POOL)"

command -v ansible-playbook >/dev/null || { echo "ansible-playbook 필요 (common-setup 마스터 단계에서 설치됨)"; exit 1; }
[[ -f "$APP_SRC/app.js" ]] || { echo "앱 소스가 $APP_SRC 에 없습니다. Vagrantfile의 synced_folder를 확인하세요."; exit 1; }

install -d "$ANSIBLE_DIR"

# --- 1. rbd 클라이언트 키링 + 최소 conf (워커 배포용) ---
echo "[block-store] rbd 클라이언트 키링 생성"
ceph auth get-or-create client.block-store \
  mon 'profile rbd' osd "profile rbd pool=${RBD_POOL}" mgr "profile rbd pool=${RBD_POOL}" \
  > "$ANSIBLE_DIR/ceph.client.block-store.keyring"
ceph config generate-minimal-conf > "$ANSIBLE_DIR/ceph.conf"

# --- 2. master: Node.js + 앱 + 중앙앱 서비스 ---
install_node() {
  command -v node >/dev/null && return 0
  echo "[block-store] Node.js 설치"
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
}
install_node

echo "[block-store] master에 앱 배치"
rm -rf "$APP_DST"
mkdir -p "$APP_DST"
cp -r "$APP_SRC/app.js" "$APP_SRC/package.json" "$APP_SRC/public" "$APP_SRC/scripts" "$APP_DST/"
( cd "$APP_DST" && npm install --omit=dev )

# --- 3. 워커 인벤토리 (cephadm vagrant 키 사용) + NODES 레지스트리 ---
cat > "$ANSIBLE_DIR/inventory.ini" <<EOF
[workers]
EOF
NODES_CSV=""
for i in $(seq 1 "$WORKER_LENGTH"); do
  host="ceph-worker-$i"
  ip="${NETWORK_PREFIX}.$((i + 10))"
  key_path="$(find "/vagrant/.vagrant/machines/$host" -path '*/private_key' -type f | head -n 1 || true)"
  if [[ -z "$key_path" ]]; then
    echo "워커 $host 의 Vagrant private key를 찾지 못했습니다." >&2
    exit 1
  fi
  echo "$host ansible_host=$ip ansible_user=vagrant ansible_ssh_private_key_file=$key_path" >> "$ANSIBLE_DIR/inventory.ini"
  NODES_CSV="${NODES_CSV:+$NODES_CSV,}${host}=http://${ip}:${AGENT_PORT}"
done
export ANSIBLE_HOST_KEY_CHECKING=False

# --- 4. 워커 배포 플레이북: ceph client → node → 앱 → RBD 마운트 → 에이전트 서비스 ---
cat > "$ANSIBLE_DIR/deploy-agent.yml" <<'PLAY'
- hosts: workers
  become: true
  vars:
    app_dst: /opt/ceph-block-store
    store_dir: /srv/rbd-store
  tasks:
    - name: /etc/ceph 디렉터리
      file: { path: /etc/ceph, state: directory, mode: '0755' }
    - name: ceph.conf 배포
      copy: { src: "{{ ceph_conf }}", dest: /etc/ceph/ceph.conf, mode: '0644' }
    - name: rbd 키링 배포
      copy: { src: "{{ ceph_keyring }}", dest: /etc/ceph/ceph.client.block-store.keyring, mode: '0600' }
    - name: Node.js 설치 (없으면)
      shell: command -v node || (curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs)
      args: { executable: /bin/bash }
    - name: 앱 디렉터리
      file: { path: "{{ app_dst }}", state: directory, mode: '0755' }
    - name: 앱 파일 복사 (app.js, package.json)
      copy: { src: "{{ app_src }}/{{ item }}", dest: "{{ app_dst }}/{{ item }}" }
      loop: [app.js, package.json]
    - name: 앱 scripts 복사
      copy: { src: "{{ app_src }}/scripts/", dest: "{{ app_dst }}/scripts/" }
    - name: 의존성 설치
      command: npm install --omit=dev
      args: { chdir: "{{ app_dst }}" }
    - name: RBD 생성/마운트 (setup-rbd-node.sh)
      shell: "POOL={{ rbd_pool }} CEPH_USER=block-store bash {{ app_dst }}/scripts/setup-rbd-node.sh"
      args: { executable: /bin/bash }
    - name: 에이전트 systemd 유닛
      copy:
        dest: /etc/systemd/system/ceph-block-agent.service
        content: |
          [Unit]
          Description=Ceph Block Store agent
          After=network-online.target
          [Service]
          WorkingDirectory={{ app_dst }}
          Environment=ROLE=agent
          Environment=STORE_DIR={{ store_dir }}
          Environment=PORT=4000
          Environment=AGENT_TOKEN={{ agent_token }}
          ExecStart=/usr/bin/node app.js
          Restart=on-failure
          [Install]
          WantedBy=multi-user.target
    - name: 에이전트 시작
      systemd: { name: ceph-block-agent, enabled: true, state: restarted, daemon_reload: true }
PLAY

echo "[block-store] 워커 에이전트 배포 (ansible)"
ansible-playbook -i "$ANSIBLE_DIR/inventory.ini" "$ANSIBLE_DIR/deploy-agent.yml" \
  -e ceph_conf="$ANSIBLE_DIR/ceph.conf" \
  -e ceph_keyring="$ANSIBLE_DIR/ceph.client.block-store.keyring" \
  -e app_src="$APP_SRC" \
  -e rbd_pool="$RBD_POOL" \
  -e agent_token="$AGENT_TOKEN"

# --- 5. master 중앙앱 systemd 서비스 ---
echo "[block-store] master 중앙앱 서비스 등록"
cat > /etc/systemd/system/ceph-block-central.service <<EOF
[Unit]
Description=Ceph Block Store central
After=network-online.target

[Service]
WorkingDirectory=$APP_DST
Environment=ROLE=central
Environment=PORT=$CENTRAL_PORT
Environment=AGENT_TOKEN=$AGENT_TOKEN
Environment=NODES=$NODES_CSV
ExecStart=/usr/bin/node app.js
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now ceph-block-central

echo "[block-store] 배포 완료"
echo "  Central UI : http://${MASTER_IP}:${CENTRAL_PORT}"
echo "  Nodes      : ${NODES_CSV}"
