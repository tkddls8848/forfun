#!/usr/bin/bash

sudo apt-get install ca-certificates curl gnupg lsb-release apt-transport-https -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get install docker.io -y
sudo systemctl enable docker
sudo systemctl start docker

# Kubernetes GPG 키 추가
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Kubernetes 저장소 추가
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# kubeadm, kubelet, kubectl 설치
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# kubelet을 자동으로 시작하도록 설정
sudo systemctl enable kubelet

#### 3. 클러스터 초기화 (마스터 노드에서)
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#### 4. 네트워크 플러그인 설치 (예: Calico)
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

#### 5. 워커 노드 연결
sudo kubeadm join k8s-master:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
