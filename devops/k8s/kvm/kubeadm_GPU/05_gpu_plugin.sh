#!/usr/bin/bash
# 05_gpu_plugin.sh
# NVIDIA Device Plugin 배포 + CUDA 테스트
# master 노드에서 실행 (single/multi 노드 공통)

set -e

DEVICE_PLUGIN_VERSION="v0.17.0"

log()        { echo "[$(date '+%H:%M:%S')] $1"; }
error_exit() { echo "❌ ERROR: $1"; exit 1; }

log "=== Phase 5: GPU Plugin 설정 시작 ==="

# ────────────────────────────────────────────
# 사전 확인
# ────────────────────────────────────────────
kubectl get nodes > /dev/null 2>&1 \
  || error_exit "kubectl 접근 불가. 03_master_init.sh 완료 후 실행하세요."

# GPU 노드 존재 여부 확인
GPU_NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
log "   현재 클러스터 노드 수: $GPU_NODE_COUNT"

# ────────────────────────────────────────────
# 1. NVIDIA Device Plugin DaemonSet 배포
# ────────────────────────────────────────────
log "1. NVIDIA Device Plugin ${DEVICE_PLUGIN_VERSION} 배포 중..."
kubectl apply -f \
  "https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/${DEVICE_PLUGIN_VERSION}/deployments/static/nvidia-device-plugin.yml"

# ────────────────────────────────────────────
# 2. Device Plugin Ready 대기
# ────────────────────────────────────────────
log "2. Device Plugin 초기화 대기 중 (최대 5분)..."
for i in $(seq 1 60); do
  STATUS=$(kubectl get pods -n kube-system \
    -l name=nvidia-device-plugin-ds \
    --no-headers 2>/dev/null | awk '{print $3}' | head -1)
  echo "  [$i/60] Device Plugin 상태: ${STATUS:-Pending}"
  [[ "$STATUS" == "Running" ]] && echo "✅ Device Plugin Running" && break
  sleep 5
done

# ────────────────────────────────────────────
# 3. 노드별 GPU 할당량 확인
# ────────────────────────────────────────────
log "3. 노드 GPU 리소스 확인..."
kubectl get nodes \
  -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu,STATUS:.status.conditions[-1].type'

# ────────────────────────────────────────────
# 4. CUDA 테스트 Pod
# ────────────────────────────────────────────
log "4. CUDA 테스트 Pod 실행 중..."
kubectl delete pod cuda-test --ignore-not-found=true

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cuda-test
spec:
  restartPolicy: Never
  containers:
  - name: cuda-test
    image: nvidia/cuda:12.1.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
      requests:
        nvidia.com/gpu: 1
EOF

log "5. 테스트 결과 대기 중 (최대 5분)..."
for i in $(seq 1 60); do
  PHASE=$(kubectl get pod cuda-test -o jsonpath='{.status.phase}' 2>/dev/null)
  echo "  [$i/60] Pod 상태: ${PHASE:-Pending}"
  [[ "$PHASE" == "Succeeded" || "$PHASE" == "Failed" ]] && break
  sleep 5
done

echo ""
echo "=== CUDA 테스트 결과 (nvidia-smi 출력) ==="
kubectl logs cuda-test

# ────────────────────────────────────────────
# 완료
# ────────────────────────────────────────────
log "=== Phase 5 완료 ==="
echo ""
echo "✅ GPU 설정 완료"
echo ""
echo "📋 유용한 명령어:"
echo "   kubectl get nodes"
echo "   kubectl describe node $(hostname) | grep -A5 'Allocatable:'"
echo "   kubectl logs cuda-test"
echo "   kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds"
