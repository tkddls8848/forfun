#!/bin/bash
# =============================================================
# 05_cnf.sh
# 역할: vFirewall(OPA) + MetalLB LoadBalancer + NetworkPolicy 배포
# 실행 위치: vm-controller (04_k8s_setup.sh 실행 후)
# 실행: bash 05_cnf.sh
# =============================================================
set -euo pipefail

LAB_DIR=~/sdn-lab/k8s
mkdir -p "${LAB_DIR}"

### ── 헬퍼 함수 ─────────────────────────────────────────────
wait_deploy() {
  local name=$1 ns=${2:-default}
  echo "    ${name} 배포 대기 중..."
  kubectl rollout status deployment/"${name}" -n "${ns}" --timeout=120s
}

### ── 1. MetalLB 설치 ────────────────────────────────────────
echo "[1/4] MetalLB LoadBalancer 설치 중..."

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

echo "    MetalLB 컨트롤러 기동 대기 중..."
kubectl wait --for=condition=ready pod \
  -l app=metallb,component=controller \
  -n metallb-system \
  --timeout=120s

# kind 노드 서브넷 자동 감지
NODE_SUBNET=$(docker network inspect kind \
  | python3 -c "import sys,json; nets=json.load(sys.stdin)[0]['IPAM']['Config']; print(nets[0]['Subnet'])" \
  2>/dev/null || echo "172.18.0.0/16")

# 서브넷에서 LB IP 풀 계산 (끝에서 .200~.250)
LB_BASE=$(echo "${NODE_SUBNET}" | cut -d'/' -f1 | cut -d'.' -f1-3)

cat > "${LAB_DIR}/metallb-config.yaml" <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: sdn-pool
  namespace: metallb-system
spec:
  addresses:
  - ${LB_BASE}.200-${LB_BASE}.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: sdn-l2adv
  namespace: metallb-system
EOF

kubectl apply -f "${LAB_DIR}/metallb-config.yaml"
echo "✅  MetalLB 설치 완료 (LB IP 풀: ${LB_BASE}.200-${LB_BASE}.250)"

### ── 2. vFirewall (OPA) 배포 ───────────────────────────────
echo "[2/4] vFirewall (OPA) 배포 중..."

cat > "${LAB_DIR}/vfirewall.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vfirewall
  namespace: default
  labels:
    component: nfv
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vfirewall
  template:
    metadata:
      labels:
        app: vfirewall
    spec:
      containers:
      - name: opa
        image: openpolicyagent/opa:latest
        args: ["run", "--server", "--addr=0.0.0.0:8181", "--log-level=info"]
        ports:
        - containerPort: 8181
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8181
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8181
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: vfirewall-svc
spec:
  selector:
    app: vfirewall
  ports:
  - port: 8181
    targetPort: 8181
EOF

kubectl apply -f "${LAB_DIR}/vfirewall.yaml"
wait_deploy vfirewall
echo "✅  vFirewall 배포 완료"

### ── 3. 웹 앱 + LoadBalancer 서비스 배포 ───────────────────
echo "[3/4] 웹 앱 (nginx x3) + MetalLB LoadBalancer 배포 중..."

cat > "${LAB_DIR}/app-with-vlb.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: web-lb
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
EOF

kubectl apply -f "${LAB_DIR}/app-with-vlb.yaml"
wait_deploy web-app

echo "    LoadBalancer IP 할당 대기 중..."
for i in $(seq 1 30); do
  LB_IP=$(kubectl get svc web-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [[ -n "${LB_IP}" ]] && break
  sleep 5
  printf "  대기 중... %d/30\r" "$i"
done
echo "✅  웹 앱 배포 완료 (External IP: ${LB_IP:-할당 대기중})"

### ── 4. NetworkPolicy 배포 ─────────────────────────────────
echo "[4/4] NetworkPolicy (vFirewall 연동) 배포 중..."

cat > "${LAB_DIR}/network-policy.yaml" <<'EOF'
# frontend → backend:8080 만 허용, 나머지 인바운드 차단
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-frontend
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: vfirewall
    ports:
    - port: 8181
---
# web-app은 외부 인바운드 허용
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-external
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - ports:
    - port: 80
EOF

kubectl apply -f "${LAB_DIR}/network-policy.yaml"

### ── 완료 안내 ──────────────────────────────────────────────
echo ""
echo "========================================"
echo "✅  CNF 전체 배포 완료!"
echo ""
echo "  전체 리소스 확인:"
echo "    kubectl get all"
echo "    kubectl get networkpolicy"
echo ""
LB_IP=$(kubectl get svc web-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "확인 필요")
echo "  웹 앱 접근 (LoadBalancer):"
echo "    curl http://${LB_IP}"
echo ""
echo "  vFirewall OPA 정책 조회:"
echo "    kubectl port-forward svc/vfirewall-svc 8181:8181 &"
echo "    curl http://localhost:8181/v1/policies"
echo ""
echo "  OPA 정책 업로드 예시:"
echo "    curl -X PUT http://localhost:8181/v1/policies/firewall \\"
echo "      -H 'Content-Type: text/plain' \\"
echo "      --data-binary @my-policy.rego"
echo "========================================"