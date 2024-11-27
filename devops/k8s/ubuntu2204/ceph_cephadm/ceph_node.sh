#!/usr/bin/bash

# install Chrony 
sudo apt-get -y install chrony

# config DNS
sudo bash -c 'cat << EOF >> /etc/hosts
10.0.1.11  ceph1
10.0.1.12  ceph2
10.0.1.13  ceph3
EOF'

# install cephadm ceph-common
sudo apt-get install cephadm -y
sudo cephadm install ceph-common

# vagrant user auth for docker
sudo usermod -aG docker $USER
newgrp docker

# external regitry connection config
sudo bash -c 'cat << EOF >> /etc/docker/daemon.json
{
    "insecure-registries" : ["ceph1:5000"]
}
EOF'
sudo systemctl restart docker

# pull ceph image from local ceph node
#docker pull ceph1:5000/ceph:v17
