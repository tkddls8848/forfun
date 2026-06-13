#!/usr/bin/env bash
set -euo pipefail

KUBESPRAY_VERSION="${KUBESPRAY_VERSION:-v2.31.0}"
KUBESPRAY_HOME="${KUBESPRAY_HOME:-$HOME/kubespray}"
VENV_PATH="${VENV_PATH:-$HOME/.venv/kubespray}"
SOURCE_INVENTORY="${SOURCE_INVENTORY:-/vagrant/inventory/inventory.ini}"
CLUSTER_INVENTORY="$KUBESPRAY_HOME/inventory/k8s-clusters"
K8S_HOSTS=(k8s-master k8s-worker1 k8s-worker2 k8s-worker3)

copy_vagrant_keys() {
  install -m 0700 -d "$HOME/.ssh"
  for host in "${K8S_HOSTS[@]}"; do
    src="/vagrant/.vagrant/machines/$host/virtualbox/private_key"
    dst="$HOME/.ssh/${host}_key"
    if [[ ! -f "$src" ]]; then
      echo "[kubespray] missing Vagrant SSH key: $src" >&2
      exit 1
    fi
    install -m 0600 "$src" "$dst"
  done
}

echo "[kubespray] installing host packages"
sudo apt-get update
sudo apt-get install -y git python3 python3-venv python3-pip bash-completion

if [[ ! -d "$KUBESPRAY_HOME/.git" ]]; then
  echo "[kubespray] cloning $KUBESPRAY_VERSION"
  git clone --branch "$KUBESPRAY_VERSION" --single-branch https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_HOME"
else
  echo "[kubespray] updating existing checkout: $KUBESPRAY_HOME"
  git -C "$KUBESPRAY_HOME" fetch --tags origin
  git -C "$KUBESPRAY_HOME" checkout "$KUBESPRAY_VERSION"
fi

if [[ ! -d "$VENV_PATH" ]]; then
  python3 -m venv "$VENV_PATH"
fi
source "$VENV_PATH/bin/activate"
python -m pip install --upgrade pip setuptools wheel
python -m pip install -r "$KUBESPRAY_HOME/requirements.txt"

if [[ ! -d "$CLUSTER_INVENTORY" ]]; then
  cp -rfp "$KUBESPRAY_HOME/inventory/sample" "$CLUSTER_INVENTORY"
fi

install -m 0755 -d "$CLUSTER_INVENTORY/group_vars/all" "$CLUSTER_INVENTORY/group_vars/k8s_cluster"
cp "$SOURCE_INVENTORY" "$CLUSTER_INVENTORY/inventory.ini"
copy_vagrant_keys

cat > "$CLUSTER_INVENTORY/group_vars/all/etcd.yml" <<EOF
etcd_kubeadm_enabled: true
EOF

cat > "$CLUSTER_INVENTORY/group_vars/k8s_cluster/k8s-cluster.yml" <<EOF
kube_network_plugin: calico
kube_proxy_strict_arp: true
EOF

cat > "$CLUSTER_INVENTORY/group_vars/k8s_cluster/addons.yml" <<EOF
metrics_server_enabled: true
helm_enabled: true
metallb_enabled: true
metallb_speaker_enabled: true
metallb_config:
  address_pools:
    primary:
      ip_range:
        - 192.168.56.128-192.168.56.143
      auto_assign: true
  layer2:
    - primary
EOF

ansible-inventory -i "$CLUSTER_INVENTORY/inventory.ini" --list >/dev/null
ansible-playbook -i "$CLUSTER_INVENTORY/inventory.ini" --become --become-user=root "$KUBESPRAY_HOME/cluster.yml"
deactivate

mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
kubectl wait --for=condition=Ready nodes --all --timeout=10m

grep -q 'kubectl completion bash' "$HOME/.bashrc" || echo 'source <(kubectl completion bash)' >> "$HOME/.bashrc"
