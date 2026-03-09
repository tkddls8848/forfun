# Docker 설치
sudo apt install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
newgrp docker

# kubectl 설치
curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# kind 설치
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x kind && sudo mv kind /usr/local/bin/

kind create cluster --config kind-config.yaml --name sdn-lab
kubectl get nodes  # 노드 확인 (처음엔 NotReady - Calico 설치 전)

# Calico 설치
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# 설치 확인 (모두 Running 될 때까지 대기)
watch kubectl get pods -n kube-system

# 노드 상태 확인
kubectl get nodes  # Ready 상태 확인

kubectl apply -f network-policy.yaml

kubectl get nodes -o wide           # 노드 IP 확인
kubectl get pods -n kube-system     # Calico 파드 확인
kubectl describe node               # 노드 상세 정보
calicoctl get nodes                 # Calico 노드 확인