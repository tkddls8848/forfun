#!/usr/bin/env bash
set -euo pipefail

KUBESPRAY_VERSION="${KUBESPRAY_VERSION:-release-2.26}"
KUBESPRAY_HOME="${KUBESPRAY_HOME:-$HOME/kubespray}"
VENV_PATH="${VENV_PATH:-$HOME/.venv/kubespray}"
SOURCE_INVENTORY="${SOURCE_INVENTORY:-/vagrant/inventory.ini}"
CLUSTER_INVENTORY="$KUBESPRAY_HOME/inventory/k8s-clusters"

echo "[kubespray] installing host packages"
sudo apt-get update
sudo apt-get install -y git python3.11 python3.11-venv python3-pip bash-completion

if [[ ! -d "$KUBESPRAY_HOME/.git" ]]; then
  echo "[kubespray] cloning $KUBESPRAY_VERSION"
  git clone --branch "$KUBESPRAY_VERSION" --single-branch https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_HOME"
else
  echo "[kubespray] using existing checkout: $KUBESPRAY_HOME"
fi

if [[ ! -d "$VENV_PATH" ]]; then
  python3.11 -m venv "$VENV_PATH"
fi
source "$VENV_PATH/bin/activate"
pip install -r "$KUBESPRAY_HOME/requirements.txt"

if [[ ! -d "$CLUSTER_INVENTORY" ]]; then
  cp -rfp "$KUBESPRAY_HOME/inventory/sample" "$CLUSTER_INVENTORY"
fi

install -m 0755 -d "$CLUSTER_INVENTORY/group_vars/all" "$CLUSTER_INVENTORY/group_vars/k8s_cluster"
cp "$SOURCE_INVENTORY" "$CLUSTER_INVENTORY/inventory.ini"

cat > "$CLUSTER_INVENTORY/group_vars/all/etcd.yml" <<EOF
etcd_kubeadm_enabled: true
EOF

cat > "$CLUSTER_INVENTORY/group_vars/k8s_cluster/k8s-cluster.yml" <<EOF
kube_network_plugin: flannel
kube_pods_subnet: 10.244.0.0/16
EOF

cat > "$CLUSTER_INVENTORY/group_vars/k8s_cluster/addons.yml" <<EOF
metrics_server_enabled: true
helm_enabled: true
metallb_enabled: true
metallb_speaker_enabled: true
metallb_ip_range:
  - "192.168.56.128/28"
EOF

ansible-inventory -i "$CLUSTER_INVENTORY/inventory.ini" --list >/dev/null
ansible-playbook -i "$CLUSTER_INVENTORY/inventory.ini" --become --become-user=root "$KUBESPRAY_HOME/cluster.yml"
deactivate

mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

grep -q 'kubectl completion bash' "$HOME/.bashrc" || echo 'source <(kubectl completion bash)' >> "$HOME/.bashrc"
