#!/usr/bin/bash

# download jenkins git repo
sudo git clone https://github.com/scriptcamp/kubernetes-jenkins
cd kubernetes-jenkins

# create namespace
kubectl create namespace devops-tools

# deploy jenkins service
kubectl apply -f .

# get initial admin password
# kubectl exec -it (pod name) cat /var/jenkins_home/secrets/initialAdminPassword -n jenkins-tools
