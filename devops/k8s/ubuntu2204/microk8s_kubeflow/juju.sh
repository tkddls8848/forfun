#!/usr/bin/bash

## install juju
sudo snap install juju  --classic --channel=3.4/stable
#sudo snap install juju --channel=3.4/stable ## no nvidia gpu
mkdir -p ~/.local/share
sudo microk8s config | juju add-k8s my-k8s --client ## naming my-k8s

## bootstraping juju and microk8s
juju bootstrap my-k8s
juju add-model kubeflow

## config filesystem
sudo sysctl fs.inotify.max_user_instances=1280
sudo sysctl fs.inotify.max_user_watches=655360

## install charmed kubeflow
juju deploy kubeflow --trust --channel=1.9/stable

## watch status juju container components
#watch -c 'juju status --color | grep -E "blocked|error|maintenance|waiting|App|Unit"'

## Get the IP address of Istio ingress gateway load balancer
IP=$(microk8s kubectl -n kubeflow get svc istio-ingressgateway-workload -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

## Configure authentication for dashboard
juju config dex-auth static-username=admin
juju config dex-auth static-password=admin

#microk8s kubectl port-forward -n kubeflow svc/istio-ingressgateway-workload 1234:80
