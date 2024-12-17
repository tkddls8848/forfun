#!/usr/bin/bash

# apply token for clustering k8s nodes
sudo apt-get install sshpass -y
sudo sshpass -p vagrant scp -o StrictHostKeyChecking=no vagrant@k8s-master:/home/vagrant/k8s_token /home/vagrant
TOKEN_VALUE=$(cat k8s_token)
sudo kubeadm join k8s-master:6443 \
        --token $TOKEN_VALUE \
        --discovery-token-unsafe-skip-ca-verification

# remove token
sudo rm -f /home/vagrant/k8s_token


