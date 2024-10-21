#!/usr/bin/bash
#run script in ubuntu OS

juju destroy-model controller
juju destroy-model kubeflow
juju kill-controller my-k8s-localhost
sudo snap remove juju
sudo snap remove microk8s
sudo rm -rf ~/.kube
sudo rm -rf ~/.local/share