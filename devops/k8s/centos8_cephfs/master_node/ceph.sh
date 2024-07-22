#!/usr/bin/bash

git clone --single-branch --branch v1.14.8 https://github.com/rook/rook.git
cd ~/rook/deploy/examples
kubectl create -f crds.yaml -f common.yaml -f operator.yaml 
kubectl create -f cluster.yaml -f toolbox.yaml -f filesystem.yaml

#kubectl apply -f ~/rook/deploy/examples/dashboard-loadbalancer.yaml

##test ceph block storage by wordpress app
#kubectl apply -f ~/rook/deploy/examples/csi/cephfs/storageclass.yaml
#kubectl apply -f ~/rook/deploy/examples/csi/rbd/storageclass.yaml
#kubectl apply -f ~/rook/deploy/examples/mysql.yaml
#kubectl apply -f ~/rook/deploy/examples/wordpress.yaml

