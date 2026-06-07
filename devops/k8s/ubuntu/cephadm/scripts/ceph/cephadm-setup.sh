#!/usr/bin/env bash
set -euo pipefail

NETWORK_PREFIX="${1:?network prefix is required}"
WORKER_LENGTH="${2:?worker length is required}"
_UNUSED_SSH_PASSWORD="${3:-}"
CEPH_VERSION="${4:-squid}"
NUM_MON="${5:-1}"
NUM_MGR="${6:-2}"
OSD_DEVICES_CSV="${7:-/dev/sdb,/dev/sdc}"

MASTER_IP="${NETWORK_PREFIX}.10"
CEPH_CLUSTER_NETWORK="${CEPH_CLUSTER_NETWORK:-${NETWORK_PREFIX}.0/24}"
CEPHADM_KEY="/root/.ssh/cephadm"
ANSIBLE_DIR="/tmp/cephadm-ansible"

echo "[cephadm] bootstrap version=$CEPH_VERSION public=${NETWORK_PREFIX}.0/24 cluster=$CEPH_CLUSTER_NETWORK"

install -m 0700 -d /root/.ssh "$ANSIBLE_DIR"
if [[ ! -f "$CEPHADM_KEY" ]]; then
  ssh-keygen -t ed25519 -f "$CEPHADM_KEY" -N ""
fi

cat > "$ANSIBLE_DIR/inventory.ini" <<EOF
[storage]
EOF

for i in $(seq 1 "$WORKER_LENGTH"); do
  host="ceph-worker-$i"
  ip="${NETWORK_PREFIX}.$((i + 10))"
  key_path="$(find "/vagrant/.vagrant/machines/$host" -path '*/private_key' -type f | head -n 1 || true)"
  if [[ -z "$key_path" ]]; then
    echo "Missing Vagrant private key for $host under /vagrant/.vagrant/machines/$host" >&2
    exit 1
  fi
  echo "$host ansible_host=$ip ansible_user=vagrant ansible_ssh_private_key_file=$key_path" >> "$ANSIBLE_DIR/inventory.ini"
done

cat > "$ANSIBLE_DIR/authorize-cephadm.yml" <<EOF
- hosts: storage
  become: true
  tasks:
    - name: Allow cephadm key for vagrant user
      ansible.builtin.authorized_key:
        user: vagrant
        key: "{{ lookup('file', '$CEPHADM_KEY.pub') }}"
        state: present
EOF

ansible-playbook -i "$ANSIBLE_DIR/inventory.ini" "$ANSIBLE_DIR/authorize-cephadm.yml"

if [[ ! -f /usr/share/keyrings/ceph-archive-keyring.gpg ]]; then
  curl -fsSL https://download.ceph.com/keys/release.asc | gpg --dearmor -o /usr/share/keyrings/ceph-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/ceph-archive-keyring.gpg] https://download.ceph.com/debian-${CEPH_VERSION} $(lsb_release -sc) main" >/etc/apt/sources.list.d/ceph.list
  apt-get update
fi

cephadm bootstrap \
  --mon-ip "$MASTER_IP" \
  --ssh-user vagrant \
  --ssh-private-key "$CEPHADM_KEY" \
  --ssh-public-key "$CEPHADM_KEY.pub" \
  --cluster-network "$CEPH_CLUSTER_NETWORK" \
  --container-backend containerd

ceph cephadm set-user vagrant
ceph cephadm set-priv-key -i "$CEPHADM_KEY"
ceph cephadm set-pub-key -i "$CEPHADM_KEY.pub"

for i in $(seq 1 "$WORKER_LENGTH"); do
  host="ceph-worker-$i"
  ip="${NETWORK_PREFIX}.$((i + 10))"
  ceph orch host add "$host" "$ip"
done

ceph orch apply mon --placement="$NUM_MON"
ceph orch apply mgr --placement="$NUM_MGR"
ceph config set global osd_pool_default_size 2

IFS=',' read -r -a OSD_DEVICES <<< "$OSD_DEVICES_CSV"
for i in $(seq 1 "$WORKER_LENGTH"); do
  host="ceph-worker-$i"
  for device in "${OSD_DEVICES[@]}"; do
    device="$(echo "$device" | xargs)"
    [[ -n "$device" ]] || continue
    ceph orch daemon add osd "${host}:${device}"
  done
done

ceph -s
ceph orch ls
