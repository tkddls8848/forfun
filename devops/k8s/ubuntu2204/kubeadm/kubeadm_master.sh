#!/usr/bin/bash

## create token for clustering k8s nodes
sudo kubeadm token generate | tee k8s_token
sudo chmod 777 k8s_token

## init kubernetes for kubeadm
sudo kubeadm init --token $(cat k8s_token) \
            --token-ttl 0 \
            --apiserver-advertise-address=172.16.10.10 \
            --pod-network-cidr=192.168.0.0/16

## configuration for authorization to use kubecli command (for vagrant user)
sudo mkdir -p /home/vagrant/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo chown vagrant:vagrant /home/vagrant/.kube/config

## Kubernetes network interface config - calico
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/tigera-operator.yaml
sudo curl -L https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/custom-resources.yaml -o calico.yaml
kubectl apply -f calico.yaml

## set bash-completion
sudo apt-get install bash-completion -y
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc

