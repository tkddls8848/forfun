#!/usr/bin/bash

## download jenkins git repo
sudo git clone https://github.com/scriptcamp/kubernetes-jenkins
cd kubernetes-jenkins

## create namespace
kubectl create namespace devops-tools

## change node name for pv, pvc
sudo sed -i 's/worker-node01/k8s-worker1/g' volume.yaml

## deploy jenkins service
kubectl apply -f .

## get initial admin password
## kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
