#!/usr/bin/bash

if ! command -v kubectl &> /dev/null; then
    echo "kubectl이 설치되어 있지 않습니다. 먼저 kubespray.sh를 실행해주세요."
    exit 1
fi

# 환경 변수 설정
export MONITORING_NAMESPACE="monitoring"
export GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 12)

# Helm 저장소 추가
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 모니터링 네임스페이스 생성
kubectl create namespace $MONITORING_NAMESPACE

# Prometheus 설정
cat > prometheus-values.yaml << EOF
server:
  persistentVolume:
    storageClass: "rook-ceph-block"
    size: 10Gi
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "1000m"
      memory: "2Gi"
alertmanager:
  persistentVolume:
    storageClass: "rook-ceph-block"
    size: 5Gi
  resources:
    requests:
      cpu: "200m"
      memory: "256Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"
EOF

# Prometheus 설치
helm install prometheus prometheus-community/prometheus \
  -f prometheus-values.yaml \
  -n $MONITORING_NAMESPACE

# Prometheus NodePort 서비스 생성
cat > prometheus-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: prometheus-nodeport
  namespace: $MONITORING_NAMESPACE
spec:
  type: NodePort
  ports:
    - port: 9090
      targetPort: 9090
      nodePort: 30001
  selector:
    app: prometheus
    component: server
EOF

kubectl apply -f prometheus-service.yaml

# Grafana 설정
cat > grafana-values.yaml << EOF
adminPassword: $GRAFANA_ADMIN_PASSWORD
persistence:
  enabled: true
  storageClassName: "rook-ceph-block"
  size: 5Gi
resources:
  requests:
    cpu: "200m"
    memory: "256Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-server.$MONITORING_NAMESPACE.svc.cluster.local
        access: proxy
        isDefault: true
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards
dashboards:
  default:
    kubernetes-cluster:
      gnetId: 7249
      revision: 1
      datasource: Prometheus
EOF

# Grafana 설치
helm install grafana grafana/grafana \
  -f grafana-values.yaml \
  -n $MONITORING_NAMESPACE

# Grafana NodePort 서비스 생성
cat > grafana-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: grafana-nodeport
  namespace: $MONITORING_NAMESPACE
spec:
  type: NodePort
  ports:
    - port: 3000
      targetPort: 3000
      nodePort: 30002
  selector:
    app.kubernetes.io/instance: grafana
EOF

kubectl apply -f grafana-service.yaml

# 접속 정보 출력
echo "Grafana 초기 관리자 비밀번호: $GRAFANA_ADMIN_PASSWORD"
echo "Prometheus URL: http://192.168.56.10:30001"
echo "Grafana URL: http://192.168.56.10:30002"