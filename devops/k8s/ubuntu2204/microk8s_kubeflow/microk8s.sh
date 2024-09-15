#!/usr/bin/bash

## install microk8s
sudo snap install microk8s --channel=1.29-strict/stable

## add user group for use microk8s
sudo usermod -a -G snap_microk8s $USER
sudo chown -f -R $USER ~/.kube
newgrp snap_microk8s

microk8s status --wait-ready

## install addons
sudo microk8s enable hostpath-storage
sudo microk8s enable ingress
sudo microk8s enable metallb:10.64.140.43-10.64.140.49
sudo microk8s enable rbac

## install juju
sudo snap install juju --channel=3.4/stable
mkdir -p ~/.local/share
microk8s config | juju add-k8s my-k8s --client ## naming my-k8s

## bootstraping juju and microk8s
juju bootstrap my-k8s
juju add-model kubeflow

## config gpu
sudo sysctl fs.inotify.max_user_instances=1280
sudo sysctl fs.inotify.max_user_watches=655360

## install charmed kubeflow
juju deploy kubeflow --trust --channel=1.9/stable

## get dashboard info
microk8s kubectl -n kubeflow get svc istio-ingressgateway-workload -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

## dashboard id and password
juju config dex-auth static-username=admin
juju config dex-auth static-password=admin