#!/usr/bin/bash

# swapoff -a to disable swapping
sudo swapoff -a
sudo sed -e '/swap/s/^/#/' -i /etc/fstab

## expand logical volume and ext4 filesystem to 100% phsical disk
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv

## install microk8s
sudo snap install microk8s --channel=1.29-strict/stable

## add user group for use microk8s
mkdir -p ~/.kube
sudo usermod -a -G snap_microk8s vagrant
sudo chown -f -R vagrant ~/.kube
newgrp snap_microk8s

## install addons
sudo microk8s enable dns
sudo microk8s enable hostpath-storage
sudo microk8s enable metallb:10.64.140.43-10.64.140.49
sudo microk8s enable rbac

## install juju
sudo snap install juju --channel=3.4/stable
mkdir -p ~/.local/share
sudo microk8s config | juju add-k8s my-k8s --client ## naming my-k8s

## bootstraping juju and microk8s
juju bootstrap my-k8s
juju add-model kubeflow

## config gpu
sudo sysctl fs.inotify.max_user_instances=1280
sudo sysctl fs.inotify.max_user_watches=655360

## install charmed kubeflow
juju deploy kubeflow --trust --channel=1.9/stable

## get istio-ingressgateway-workload dashboard svc ip address info
sudo microk8s kubectl -n kubeflow get svc istio-ingressgateway-workload -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

## config dashboard id and password
juju config dex-auth static-username=admin
juju config dex-auth static-password=admin

#ssh -L 1111:10.152.183.37:8082 vagrant@192.168.10.10
#ssh -D 9999 vagrant@192.168.10.10

#microk8s kubectl port-forward -n istio-system $(microk8s kubectl get pod -n istio-system -l istio=ingressgateway -o jsonpath='{.items[0].metadata.name}') 8080:80