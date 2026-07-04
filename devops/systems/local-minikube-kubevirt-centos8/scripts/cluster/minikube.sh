#!/usr/bin/bash

## install docker (no docker in Rocky Linux)
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER && newgrp docker

MINIKUBE_VERSION="${MINIKUBE_VERSION:-v1.38.1}"

## install Minikube
curl -LO "https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-amd64"
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm -f minikube-linux-amd64

