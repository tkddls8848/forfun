#!/bin/bash
#=========================================================================
# Prometheus & Grafana 설치 스크립트
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

# kube-prometheus-stack 네임스페이스
export MONITORING_NAMESPACE="monitoring"

#=========================================================================
# 1. 필요한 Helm 저장소 추가
#=========================================================================
echo -e "\n[단계 1/4] Helm 저장소 추가 중..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

#=========================================================================
# 2. 모니터링 네임스페이스 생성
#=========================================================================
echo -e "\n[단계 2/4] 모니터링 네임스페이스 생성 중..."
kubectl create namespace $MONITORING_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

#=========================================================================
# 3. values.yaml 파일 생성
#=========================================================================
echo -e "\n[단계 3/4] values.yaml 파일 생성 중..."
cat > /tmp/prometheus-values.yaml << EOF
# kube-prometheus-stack 설정
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: ceph-rbd-sc
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
  service:
    type: NodePort
    nodePort: 30090

prometheus-node-exporter:
  hostNetwork: false  # 가장 중요한 수정사항
  service:
    port: 9100
    targetPort: 9101
  ports:
    metrics:
      port: 9101
      targetPort: 9101
      name: metrics
  extraArgs:
    - --web.listen-address=:9101

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: ceph-rbd-sc
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 2Gi
  service:
    type: NodePort
    nodePort: 30093

grafana:
  persistence:
    type: pvc
    enabled: true
    storageClassName: ceph-rbd-sc
    accessModes:
      - ReadWriteOnce
    size: 5Gi
  service:
    type: NodePort
    nodePort: 30080
  adminPassword: admin
EOF

#=========================================================================
# 4. Prometheus & Grafana 설치
#=========================================================================
echo -e "\n[단계 4/4] Prometheus & Grafana 설치 중..."
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace $MONITORING_NAMESPACE \
  --values /tmp/prometheus-values.yaml

echo -e "\n[완료] Prometheus 및 Grafana 설치 완료"
echo "Prometheus URL: http://<master-ip>:30090"
echo "Grafana URL: http://<master-ip>:30080 (사용자: admin, 비밀번호: admin)"
echo "AlertManager URL: http://<master-ip>:30093"