#!/usr/bin/bash

## ceph blocksystem
cd ~/rook/deploy/examples/
kubectl apply -f ~/rook/deploy/examples/csi/cephfs/storageclass.yaml

# test ceph block storage by wordpress app
kubectl apply -f mysql.yaml
kubectl apply -f wordpress.yaml

