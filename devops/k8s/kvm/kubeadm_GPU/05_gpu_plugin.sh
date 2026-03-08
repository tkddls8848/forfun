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

# 기존 DaemonSet 삭제 후 재생성 (이전 patch 상태 누적 방지)
kubectl delete daemonset -n kube-system nvidia-device-plugin-daemonset \
  --ignore-not-found=true 2>/dev/null || true

# RuntimeClass 등록 (nvidia runtime을 k8s에서 명시적으로 선택할 수 있도록)
cat <<'EOF' | kubectl apply -f -
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
EOF

kubectl apply -f \
  "https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/${DEVICE_PLUGIN_VERSION}/deployments/static/nvidia-device-plugin.yml"

# nvidia 라이브러리 스테이징 경로 (02_node_setup.sh에서 worker에 직접 생성)
# - master VM → worker 호스트 간 SSH 의존 제거
# - 02_node_setup.sh 실행 완료 후 worker에 /usr/local/nvidia/lib64 존재해야 함
NVIDIA_LIB_STAGING="/usr/local/nvidia/lib64"
WORKER_NODE=$(kubectl get nodes --no-headers \
  | grep -v "control-plane\|master" | awk '{print $1}' | head -1)
log "   GPU worker 노드: ${WORKER_NODE:-감지 안됨}"

# 패치: privileged + nvidia 전용 hostPath 마운트
# - privileged: /dev/nvidia* 디바이스 직접 접근
# - hostPath: nvidia 라이브러리만 있는 디렉토리 → libc 등 시스템 라이브러리 충돌 방지
# - runtime injection 불필요 → containerd nvidia runtime 설정 무관
kubectl patch daemonset -n kube-system nvidia-device-plugin-daemonset --type=json \
  --patch "[
  {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args\",\"value\":[\"--device-discovery-strategy=nvml\"]},
  {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/securityContext\",\"value\":{\"privileged\":true}},
  {\"op\":\"add\",\"path\":\"/spec/template/spec/volumes/-\",\"value\":{\"name\":\"nvidia-libs\",\"hostPath\":{\"path\":\"${NVIDIA_LIB_STAGING}\"}}},
  {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/volumeMounts/-\",\"value\":{\"name\":\"nvidia-libs\",\"mountPath\":\"/usr/local/nvidia/lib64\",\"readOnly\":true}}
]"

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
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu,STATUS:.status.conditions[-1].type'

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
    command:
    - /bin/sh
    - -c
    - |
      echo "=== GPU 디바이스 ==="
      ls /dev/nvidia* 2>/dev/null || echo "ERROR: /dev/nvidia* 없음"
      echo "=== NVIDIA_VISIBLE_DEVICES ==="
      echo "${NVIDIA_VISIBLE_DEVICES:-NOT_SET}"
      echo "=== 완료 ==="
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
echo "=== CUDA 테스트 결과 ==="
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
echo "   kubectl describe node ${WORKER_NODE:-<worker>} | grep -A5 'Allocatable:'"
echo "   kubectl logs cuda-test"
echo "   kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds"
