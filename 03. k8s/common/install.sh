#!/usr/bin/bash

# install NFS server
sudo yum install -y nfs nfs-utils cifs-utils rpc-bind

# make share folder
sudo mkdir -p /share/nfs
mount -t nfs 192.168.1.100:/share/nfs /share/nfs

# install packages for util
sudo yum install -y sshpass

# install packages for docker
sudo yum install -y yum-utils

# docker repository
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# yum update and install docker
sudo yum update -y && sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl enable --now docker

# Update the configuration
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# kubernetes repository (temporary, google repository is moving)
sudo bash -c 'cat << EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl
EOF'
# kubernetes repository (legacy repository)
#cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
#[kubernetes]
#name=Kubernetes
#baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
#enabled=1
#gpgcheck=1
#gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
#exclude=kubelet kubeadm kubectl
#EOF

# install kubernetes
sudo yum install -y kubelet-1.28.1 kubeadm-1.28.1 kubectl-1.28.1 --disableexcludes=kubernetes
sudo systemctl enable --now kubelet
