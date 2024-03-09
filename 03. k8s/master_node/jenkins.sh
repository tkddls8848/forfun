#!/usr/bin/bash

# make NFS pv, pvc object
sudo bash -c 'cat << EOF > nfs-persistent-volume.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: 192.168.1.100 ## NFS server node ip
    path: /nfs
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 5Gi
EOF'
kubectl apply -f nfs-persistent-volume.yaml

# install jenkins using helm and apply values.yaml config file

helm repo add jenkins https://charts.jenkins.io
helm repo update
kubectl create namespace jenkins
sudo bash -c 'cat << EOF > values.yaml
controller:
  serviceType: "NodePort"
  adminPassword: "myPassword"
persistence:
  existingClaim: "nfs-pvc"
EOF'
helm install jenkins jenkins/jenkins --namespace jenkins -f values.yaml

# save initial admin password
# kubectl exec -it svc/my-jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo | tee jenkins_password.txt
