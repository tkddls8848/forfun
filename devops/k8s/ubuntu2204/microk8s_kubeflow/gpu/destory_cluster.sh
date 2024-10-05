#!/usr/bin/bash
#run script in ubuntu OS

juju destroy-model controller
juju destroy-model kubeflow

juju kill-controller my-k8s-local

sudo snap remove juju

sudo snap remove microk8s