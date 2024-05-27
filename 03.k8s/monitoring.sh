#!/usr/bin/bash

# add helm repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# create namespace for installing Prometheus and Grafana
kubectl create namespace monitoring

helm inspect values prometheus-community/prometheus > values.yaml
sed -i 's/# storageClass: "-"/storageClass: "nfs-client"/g' values.yaml
helm install prometheus -f values.yaml prometheus-community/prometheus -n monitoring

sudo mkdir /data
touch ~/prometheus-server-vol.yaml
sudo chown vagrant ~/prometheus-server-vol.yaml
bash -c 'cat << EOF > ~/prometheus-server-vol.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-server
  namespace: monitoring
spec:
  selector:
    matchLabels:
      type: local
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-storage
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: prometheus-server-pv
  namespace: monitoring
  labels:
    type: local
spec:
  capacity:
    storage: 8Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  hostPath:
    path: /data
EOF
'
kubectl apply -f prometheus-server-vol.yaml --force

touch ~/prometheus-alertmanager-vol.yaml
sudo chown vagrant ~/prometheus-alertmanager-vol.yaml
bash -c 'cat << EOF > ~/prometheus-alertmanager-vol.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: prometheus-alertmanager-pv
  namespace: monitoring
  labels:
    app.kubernetes.io/instance: prometheus
    app.kubernetes.io/name: alertmanager
spec:
  capacity:
    storage: 8Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  hostPath:
    path: /alertmanager/data
EOF
'
kubectl apply -f prometheus-alertmanager-vol.yaml --force

# install Prometheus by Helm
helm install prometheus prometheus-community/prometheus --namespace monitoring

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
cd ~
kubectl get svc -n monitoring -o yaml grafana > grafana.yaml
sudo chmod +x grafana.yaml
sudo sed -i 's/type: ClusterIP/type: NodePort/g' grafana.yaml
kubectl replace --force -f grafana.yaml