#!/usr/bin/env bash
set -euo pipefail

KUBESPRAY_VERSION="${KUBESPRAY_VERSION:-release-2.25}"
KUBESPRAY_HOME="${KUBESPRAY_HOME:-$HOME/kubespray}"
VENV_PATH="${VENV_PATH:-$HOME/.venv/kubespray}"
SOURCE_INVENTORY="${SOURCE_INVENTORY:-/vagrant/inventory.ini}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11.9}"
CLUSTER_INVENTORY="$KUBESPRAY_HOME/inventory/k8s-clusters"

sudo dnf install -y git gcc zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel openssl-devel tk-devel libffi-devel wget tar make bash-completion

if ! command -v python3.11 >/dev/null 2>&1; then
  cd "$HOME"
  if [[ ! -d "Python-$PYTHON_VERSION" ]]; then
    wget -O "Python-$PYTHON_VERSION.tgz" "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"
    tar xzf "Python-$PYTHON_VERSION.tgz"
  fi
  cd "Python-$PYTHON_VERSION"
  ./configure --enable-optimizations
  make -j"$(nproc)"
  sudo make altinstall
fi

if [[ ! -d "$KUBESPRAY_HOME/.git" ]]; then
  git clone --branch "$KUBESPRAY_VERSION" --single-branch https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_HOME"
fi

if [[ ! -d "$VENV_PATH" ]]; then
  python3.11 -m venv "$VENV_PATH"
fi
source "$VENV_PATH/bin/activate"
pip install -r "$KUBESPRAY_HOME/requirements.txt"

if [[ ! -d "$CLUSTER_INVENTORY" ]]; then
  cp -rfp "$KUBESPRAY_HOME/inventory/sample" "$CLUSTER_INVENTORY"
fi

mkdir -p "$CLUSTER_INVENTORY/group_vars/all" "$CLUSTER_INVENTORY/group_vars/k8s_cluster"
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
  - "192.168.1.128/28"
EOF

ansible-inventory -i "$CLUSTER_INVENTORY/inventory.ini" --list >/dev/null
ansible-playbook -i "$CLUSTER_INVENTORY/inventory.ini" --become --become-user=root "$KUBESPRAY_HOME/cluster.yml"
deactivate

sudo mkdir -p /home/vagrant/.kube /root/.kube
sudo cp -f /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo cp -f /etc/kubernetes/admin.conf /root/.kube/config
sudo chown vagrant:vagrant /home/vagrant/.kube/config

grep -q 'kubectl completion bash' "$HOME/.bashrc" || echo 'source <(kubectl completion bash)' >> "$HOME/.bashrc"
grep -q "alias k=kubectl" "$HOME/.bashrc" || echo 'alias k=kubectl' >> "$HOME/.bashrc"
