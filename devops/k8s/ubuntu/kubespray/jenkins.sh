#!/usr/bin/bash

# kubectl 사용 가능 여부 확인
if ! command -v kubectl &> /dev/null; then
    echo "kubectl이 설치되어 있지 않습니다. 먼저 kubespray.sh를 실행해주세요."
    exit 1
fi

# 환경 변수 설정
export JENKINS_NAMESPACE="devops-tools"
export JENKINS_ADMIN_PASSWORD=$(openssl rand -base64 12)

# 네임스페이스 생성
kubectl create namespace $JENKINS_NAMESPACE

# Jenkins 설치
cat > jenkins-values.yaml << EOF
controller:
  adminPassword: $JENKINS_ADMIN_PASSWORD
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "1000m"
      memory: "2Gi"
  storageClass: "rook-ceph-block"
  persistence:
    size: 10Gi
agent:
  resources:
    requests:
      cpu: "200m"
      memory: "256Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"
EOF

# Helm으로 Jenkins 설치
helm repo add jenkins https://charts.jenkins.io
helm repo update
helm install jenkins jenkins/jenkins -f jenkins-values.yaml -n $JENKINS_NAMESPACE

# NodePort 서비스 생성
cat > jenkins-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: jenkins-nodeport
  namespace: $JENKINS_NAMESPACE
spec:
  type: NodePort
  ports:
    - port: 8080
      targetPort: 8080
      nodePort: 30000
  selector:
    app.kubernetes.io/instance: jenkins
EOF

kubectl apply -f jenkins-service.yaml

# 초기 관리자 비밀번호 출력
echo "Jenkins 초기 관리자 비밀번호: $JENKINS_ADMIN_PASSWORD"
echo "Jenkins URL: http://192.168.56.10:30000"
