#!/usr/bin/bash

# install NFS server
sudo yum install nfs-utils

# make share folder
sudo mkdir -p /var/nfs/general

# enroll share folder
sudo bash -c 'cat << EOF > /etc/exports
/var/nfs/general *(rw,sync,no_subtree_check,no_root_squash)
EOF'
sudo systemctl restart nfs-server

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
    server: 192.168.1.10 ## master node ip
    path: /var/nfs/general
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
sudo bash -c 'cat << EOF > values.yaml
controller:
  serviceType: "NodePort"
persistence:
  existingClaim: "nfs-pvc"
EOF'
helm install my-jenkins jenkins/jenkins -f values.yaml

# save initial admin password
# kubectl exec --namespace default -it svc/my-jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo | tee jenkins_password.txt