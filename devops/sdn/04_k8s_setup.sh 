#!/bin/bash
# =============================================================
# 04_k8s_setup.sh
# 역할: Docker + kubectl + kind 설치 → 멀티노드 K8s 클러스터 + Calico
# 실행 위치: vm-controller (ssh sdn@192.168.100.10)
# 실행: bash 04_k8s_setup.sh  (sudo 불필요, 내부에서 처리)
# =============================================================
set -euo pipefail

CLUSTER_NAME="sdn-lab"
KIND_VERSION="v0.22.0"
KUBECTL_VERSION=$(curl -s https://dl.k8s.io/release/stable.txt)
LAB_DIR=~/sdn-lab/k8s

mkdir -p "${LAB_DIR}"

### ── 1. Docker 설치 ─────────────────────────────────────────
echo "[1/6] Docker 설치 중..."
if ! command -v docker &>/dev/null; then
  sudo apt update -qq
  sudo apt install -y docker.io
  sudo systemctl enable --now docker
  sudo usermod -aG docker "$USER"
  echo "    ⚠️  docker 그룹 적용을 위해 newgrp docker 실행 필요"
else
  echo "    ↳ Docker 이미 설치됨: $(docker --version)"
fi
sudo systemctl start docker
echo "✅  Docker 준비 완료"

### ── 2. kubectl 설치 ────────────────────────────────────────
echo "[2/6] kubectl ${KUBECTL_VERSION} 설치 중..."
if ! command -v kubectl &>/dev/null; then
  curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
fi
echo "    kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
echo "✅  kubectl 설치 완료"

### ── 3. kind 설치 ───────────────────────────────────────────
echo "[3/6] kind ${KIND_VERSION} 설치 중..."
if ! command -v kind &>/dev/null; then
  curl -sLo kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
  chmod +x kind
  sudo mv kind /usr/local/bin/
fi
echo "    kind: $(kind version)"
echo "✅  kind 설치 완료"

### ── 4. kind 클러스터 설정 파일 생성 ───────────────────────
echo "[4/6] kind 클러스터 설정 파일 생성 중..."
cat > "${LAB_DIR}/kind-config.yaml" <<'EOF'
# kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true        # Calico 직접 설치용
  podSubnet: "192.168.0.0/16"
  serviceSubnet: "10.96.0.0/16"
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 8080
    protocol: TCP
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
- role: worker
  extraPortMappings:
  - containerPort: 30080
    hostPort: 30080
- role: worker
  extraPortMappings:
  - containerPort: 30081
    hostPort: 30081
- role: worker
EOF

### ── 5. 클러스터 생성 ───────────────────────────────────────
echo "[5/6] kind 클러스터 생성 중 (약 3~5분 소요)..."

# 기존 클러스터 삭제
kind delete cluster --name "${CLUSTER_NAME}" 2>/dev/null || true

# 클러스터 생성 (docker 그룹 권한 필요)
if groups | grep -q docker; then
  kind create cluster \
    --config  "${LAB_DIR}/kind-config.yaml" \
    --name    "${CLUSTER_NAME}"
else
  sudo kind create cluster \
    --config  "${LAB_DIR}/kind-config.yaml" \
    --name    "${CLUSTER_NAME}"
  mkdir -p ~/.kube
  sudo kind get kubeconfig --name "${CLUSTER_NAME}" > ~/.kube/config
  sudo chown "$USER":"$USER" ~/.kube/config
fi

echo "✅  kind 클러스터 생성 완료"
kubectl get nodes

### ── 6. Calico CNI 설치 ─────────────────────────────────────
echo "[6/6] Calico CNI 설치 중..."

kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

echo "    Calico 파드 기동 대기 중 (최대 3분)..."
kubectl wait --for=condition=ready pod \
  -l k8s-app=calico-node \
  -n kube-system \
  --timeout=180s

kubectl get nodes
kubectl get pods -n kube-system

echo ""
echo "========================================"
echo "✅  K8s 클러스터 + Calico 설치 완료!"
echo ""
echo "  클러스터 정보:"
echo "    kubectl cluster-info"
echo "    kubectl get nodes -o wide"
echo "    kubectl get pods -n kube-system"
echo ""
echo "  다음 단계:"
echo "    bash 05_cnf.sh  # vFirewall + MetalLB + NetworkPolicy 배포"
echo "========================================"