#!/usr/bin/bash

# init kubernetes for kubeadm
sudo kubeadm init --token 123456.1234567890123456 \
            --token-ttl 0 \
            --apiserver-advertise-address=192.168.1.10 \
            --pod-network-cidr=10.244.0.0/16
 
# configuration for authorization to use kubecli command (for root user)
sudo mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf

# Kubernetes network interface config - calico
sudo curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.4/manifests/calico.yaml -O
sudo sed -i -e 's?cidr: 192.168.0.0\/16?cidr: 10.224.0.0\/16?g' calico.yaml
sudo kubectl apply -f calico.yaml

# set bash-completion
sudo yum install bash-completion -y
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc

# make test.yaml file
touch test.yaml
sudo bash -c 'cat <<EOF > ./test.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:latest
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: NodePort
EOF'