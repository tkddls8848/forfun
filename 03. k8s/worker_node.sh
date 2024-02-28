#!/usr/bin/bash

# apply token for clustering k8s nodes
sudo sshpass -p vagrant scp -o StrictHostKeyChecking=no vagrant@192.168.1.10:/home/vagrant/k8s_token /home/vagrant
TOKEN_VALUE=$(cat k8s_token)

# worker node config
sudo kubeadm join 192.168.1.10:6443 \
        --token $(cat k8s_token) \
        --discovery-token-unsafe-skip-ca-verification

# remove token
sudo rm -f /home/vagrant/k8s_token