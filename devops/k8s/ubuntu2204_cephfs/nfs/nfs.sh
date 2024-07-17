#!/usr/bin/bash

sudo apt-get update -y
sudo timedatectl set-timezone Asia/Seoul

## config nfs directory system
sudo apt-get install nfs-kernel-server -y

# enroll directory for nfs server
sudo mkdir /mnt/share
sudo mkdir /mnt/share/prometheus-server
sudo mkdir /mnt/share/prometheus-alertmanager
sudo chown -R nobody:nogroup /mnt/share
sudo bash -c 'echo "/mnt/share  192.168.56.10/24(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports'
sudo bash -c 'echo "/mnt/share/prometheus-server  192.168.56.10/24(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports'
sudo bash -c 'echo "/mnt/share/prometheus-alertmanager  192.168.56.10/24(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports'

# restart nfs
sudo exportfs -a
sudo systemctl restart nfs-kernel-server.service

## sample nginx pod object
sudo bash -c 'cat << EOF > /mnt/share/nfs-volume-sample.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
    volumeMounts:
    - name: nfs-volume
      mountPath: /data
  volumes:
  - name: nfs-volume
    persistentVolumeClaim:
      claimName: pvc-nfs
---
apiVersion: v1
kind: PersistentVolume
metadata:
    name: pv-nfs
    labels:
        type: nfs
spec:
    storageClassName: ""
    capacity:
        storage: 10Gi
    accessModes:
        - ReadWriteMany
    nfs:
        path: /mnt/share
        server: 192.168.56.100
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
    name: pvc-nfs
spec:
    selector:
        matchLabels:
            type: nfs
    accessModes:
        - ReadWriteMany
    resources:
        requests:
            storage: 5Gi
    storageClassName: ""
EOF'