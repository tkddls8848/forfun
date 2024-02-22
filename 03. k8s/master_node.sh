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

# Backup the original file
#sudo cp custom-resources.yaml custom-resources.yaml.backup
#sudo cp calico.yaml calico.yaml.backup

#sudo sed -i -e 's?cidr: 192.168.0.0\/16?cidr: 10.224.0.0\/16?g' custom-resources.yaml
#sudo sed -i -e 's?cidr: 192.168.0.0\/16?cidr: 10.224.0.0\/16?g' calico.yaml
#sudo kubectl create -f custom-resources.yaml
#sudo kubectl create -f calico.yaml

# set bash-completion
sudo yum install bash-completion -y

echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc