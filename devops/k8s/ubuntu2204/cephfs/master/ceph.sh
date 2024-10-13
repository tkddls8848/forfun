#!/usr/bin/bash

git clone --single-branch --branch v1.14.5 https://github.com/rook/rook.git
cd ~/rook/deploy/examples

kubectl create -f crds.yaml -f common.yaml -f operator.yaml
kubectl create -f cluster.yaml -f toolbox.yaml

# ceph objectstorage
kubectl create -f object.yaml ## "my-store" object store 생성
kubectl create -f storageclass-bucket-delete.yaml -f object-bucket-claim-delete.yaml ## "my-store" object 버킷 및 storageclass 생성
kubectl create -f rgw-external.yaml ## "my-store" object 버킷 액세스를 위한 서비스 오브젝트 생성

## ceph filesystem
#kubectl create -f filesystem.yaml

## ceph blocksystem
#kubectl apply -f ~/rook/deploy/examples/csi/cephfs/storageclass.yaml

kubectl apply -f ~/rook/deploy/examples/dashboard-loadbalancer.yaml

# test ceph block storage by wordpress app
kubectl apply -f ~/rook/deploy/examples/mysql.yaml
kubectl apply -f ~/rook/deploy/examples/wordpress.yaml

