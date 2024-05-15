#!/usr/bin/bash

# download jenkins git repo
sudo git clone https://github.com/scriptcamp/kubernetes-jenkins
cd kubernetes-jenkins

# create namespace
kubectl create namespace devops-tools

# deploy jenkins service
kubectl apply -f .

# get initial admin password
# kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
