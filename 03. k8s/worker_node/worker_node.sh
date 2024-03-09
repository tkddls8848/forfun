#!/usr/bin/bash

# apply token for clustering k8s nodes
sudo sshpass -p vagrant scp -o StrictHostKeyChecking=no vagrant@192.168.1.10:/home/vagrant/k8s_token /home/vagrant
sudo ssh-keygen -R 192.168.1.10
sudo rm -f /root/.ssh/known_hosts
sudo touch /root/.ssh/known_hosts

# worker node config
sudo kubeadm join 192.168.1.10:6443 \
        --token $(cat k8s_token) \
        --discovery-token-unsafe-skip-ca-verification

# remove token
sudo rm -f /home/vagrant/k8s_token

# nfs mount and maintain volume
sudo mount -t nfs 192.168.1.100:/nfs /nfs
sudo bash -c 'cat << EOF > /etc/fstab
192.168.1.100:/nfs /nfs nfs default 0 0
EOF
'
