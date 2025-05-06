#!/bin/bash

# 필요한 환경 변수 확인
if [ -z "$K8S_SECRET_NAME" ] || [ -z "$K8S_CSI_NAMESPACE" ] || [ -z "$CEPH_CSI_USER" ]; then
  echo "Error: 필요한 환경 변수가 설정되지 않았습니다."
  exit 1
fi

# 기존 사용자 삭제
echo "기존 사용자 삭제 중..."
ceph auth del client.$CEPH_CSI_USER 2>/dev/null || true

# 모든 권한을 가진 새 사용자 생성 (admin과 유사한 권한)
echo "관리자 권한을 가진 새 사용자 생성 중..."
ceph auth add client.$CEPH_CSI_USER mds 'allow rw' mon 'allow r' osd 'allow rw' mgr 'allow *'

# 생성된 사용자 권한 확인
echo "생성된 사용자 권한 확인:"
ceph auth get client.$CEPH_CSI_USER

# 사용자 키 가져오기
CEPH_USER_KEYRING=$(ceph auth get-key client.$CEPH_CSI_USER)

# 네임스페이스 생성
echo "네임스페이스 $K8S_CSI_NAMESPACE 생성 중..."
kubectl create namespace $K8S_CSI_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Secret YAML 파일 생성
cat > ceph-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: $K8S_SECRET_NAME
  namespace: $K8S_CSI_NAMESPACE
stringData:
  adminID: $CEPH_CSI_USER
  adminKey: $CEPH_USER_KEYRING
  userID: $CEPH_CSI_USER
  userKey: $CEPH_USER_KEYRING
EOF

echo "YAML 파일 'ceph-secret.yaml'이 성공적으로 생성되었습니다."

# Secret 적용
echo "Secret을 Kubernetes에 적용 중..."
kubectl apply -f ceph-secret.yaml

# 기존 PVC 삭제 (문제가 있는 경우)
echo "기존 PVC를 정리 중..."
kubectl delete pvc --all 2>/dev/null || true

# CSI 드라이버 파드 재시작
echo "CSI 드라이버 파드를 재시작합니다..."
kubectl -n $K8S_CSI_NAMESPACE rollout restart deployment ceph-csi-cephfs-release-provisioner

# 대기 시간 설정 (초)
WAIT_TIME=120
echo "CSI 드라이버 배포를 위해 ${WAIT_TIME}초 대기합니다..."
# 카운터 초기화
counter=0
while [ $counter -lt $WAIT_TIME ]; do
  # 화면 지우기 없이 경과 시간만 업데이트
  echo -ne "CSI 드라이버 배포를 위해 ${WAIT_TIME}초 대기합니다...(경과시간: ${counter}초)\r"
  sleep 1
  counter=$((counter + 1))
done
echo -e "CSI 드라이버 배포를 위해 ${WAIT_TIME}초 대기합니다...(경과시간: ${WAIT_TIME}초) - 완료"

# CSI 프로비저너 파드 상태 확인
echo "CSI 프로비저너 파드 상태:"
kubectl -n $K8S_CSI_NAMESPACE get pods | grep provisioner