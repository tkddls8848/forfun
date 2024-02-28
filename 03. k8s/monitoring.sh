#!/usr/bin/bash

# install helm
sudo yum install vim git -y
export PATH=$PATH:/usr/local/bin
source ~/.bashrc
sudo curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
sudo chmod 700 get_helm.sh
./get_helm.sh

# add helm repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Prometheus 및 Grafana 설치를 위한 Namespace 생성
kubectl create namespace monitoring

# Helm을 통한 Prometheus 설치
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --set alertmanager.persistentVolume.storageClass="gp2",server.persistentVolume.storageClass="gp2"

# Helm을 통한 Grafana 설치
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install grafana grafana/grafana \
  --namespace monitoring \
  --set persistence.storageClassName="gp2",adminPassword='YOUR_GRAFANA_PASSWORD' \
  --set datasources."datasources\.yaml".apiVersion=1 \
  --set datasources."datasources\.yaml".datasources[0].name=Prometheus \
  --set datasources."datasources\.yaml".datasources[0].type=prometheus \
  --set datasources."datasources\.yaml".datasources[0].url=http://prometheus-server.monitoring.svc.cluster.local \
  --set datasources."datasources\.yaml".datasources[0].access=proxy \
  --set datasources."datasources\.yaml".datasources[0].isDefault=true

# Grafana에 대한 admin 비밀번호 설정 주의: 'YOUR_GRAFANA_PASSWORD'를 실제 사용할 비밀번호로 변경하세요.

kubectl get svc -n monitoring -o yaml grafana > grafana.yaml
sudo chmod 777 grafana.yaml
sudo sed -i 's/type: ClusterIP/type: NodePort/g' grafana.yaml
kubectl apply -f grafana.yaml
