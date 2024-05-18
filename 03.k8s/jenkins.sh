#!/usr/bin/bash

# download jenkins git repo
sudo git clone https://github.com/scriptcamp/kubernetes-jenkins
cd kubernetes-jenkins

# create namespace
kubectl create namespace devops-tools

# change node name for pv, pvc
export WORKER_NODE_NAME=$1
sed -i 's/worker-node01/${WORKER_NODE_NAME}/g' volume.yaml

# deploy jenkins service
kubectl apply -f .

# get initial admin password
# kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
