#!/usr/bin/bash

# download jenkins git repo
sudo git clone https://github.com/scriptcamp/kubernetes-jenkins
cd kubernetes-jenkins

# create namespace
kubectl create namespace jenkins-tools

# modify namespace value
sudo sed -i 's/namespace: devops-tools/namespace: jenkins-tools/g' *.yaml

# modify node name in pv config
sudo sed -i 's/- worker-node01/- k8s-worker1/g' volume.yaml

# deploy jenkins service
kubectl apply -f .

# get initial admin password
# kubectl exec -it (pod name) cat /var/jenkins_home/secrets/initialAdminPassword -n jenkins-tools
