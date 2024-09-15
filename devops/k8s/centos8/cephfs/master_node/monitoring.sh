#!/usr/bin/bash

# add helm repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# create namespace for installing Prometheus and Grafana
kubectl create namespace monitoring

# install Prometheus by Helm
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --set alertmanager.persistentVolume.storageClass="gp2",server.persistentVolume.storageClass="gp2"

# install Grafana by Helm
helm upgrade --install grafana grafana/grafana \
  --namespace monitoring \
  --set persistence.storageClassName="gp2",adminPassword='password' \
  --set datasources."datasources\.yaml".apiVersion=1 \
  --set datasources."datasources\.yaml".datasources[0].name=Prometheus \
  --set datasources."datasources\.yaml".datasources[0].type=prometheus \
  --set datasources."datasources\.yaml".datasources[0].url=http://prometheus-server.monitoring.svc.cluster.local \
  --set datasources."datasources\.yaml".datasources[0].access=proxy \
  --set datasources."datasources\.yaml".datasources[0].isDefault=true

# Grafana admin password: initial password is 'password'

# config Grafana service type to NodePort
kubectl get svc -n monitoring -o yaml grafana > grafana.yaml
sudo chmod  grafana.yaml
sudo sed -i 's/type: ClusterIP/type: NodePort/g' grafana.yaml
kubectl apply -f grafana.yaml

