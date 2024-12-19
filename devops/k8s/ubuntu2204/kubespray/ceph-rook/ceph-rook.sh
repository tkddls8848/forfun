#!/usr/bin/bash

## clone rook-ceph
git clone --single-branch --branch v1.14.5 https://github.com/rook/rook.git
cd ~/rook/deploy/examples

## install rook-ceph component
kubectl create -f crds.yaml -f common.yaml -f operator.yaml
kubectl create -f cluster.yaml -f toolbox.yaml

## install rook-ceph dashboard
kubectl apply -f dashboard-loadbalancer.yaml
