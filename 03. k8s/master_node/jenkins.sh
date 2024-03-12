#!/usr/bin/bash

# download jenkins git repo
sudo git clone https://github.com/scriptcamp/kubernetes-jenkins
cd kubernetes-jenkins

# create namespace
kubectl create namespace devops-tools

# modify node name in pv config
sudo sed -i 's/- worker-node01/- k8s-worker1/' volume.yaml

# deploy jenkins service
kubectl create -f volume.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# get initial admin password
# kubectl exec -it (pod name) cat /var/jenkins_home/secrets/initialAdminPassword -n devops-tools
