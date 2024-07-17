#!/usr/bin/bash

########### 1. install openssl 1.1.1 ###########
## repo update
sudo yum -y update
## remove openssl 1.0.1k
sudo yum -y remove openssl openssl-devel

## install packages for openssl 1.1.1
sudo yum install -y gcc gcc-c++ pcre-devel zlib-devel perl wget libffi-devel bzip2-devel git

## download and install openssl 1.1.1
cd /usr/local/src
sudo chown -R $(whoami):$(whoami) /usr/local/src
wget https://www.openssl.org/source/openssl-1.1.1k.tar.gz
tar xvfz openssl-1.1.1k.tar.gz
cd openssl-1.1.1k
./config --prefix=/usr/local/ssl --openssldir=/usr/local/ssl shared zlib
make
sudo make install

## make config file for openssl 1.1.1
sudo touch /etc/ld.so.conf.d/openssl-1.1.1k.conf
sudo chown $(whoami):$(whoami) /etc/ld.so.conf.d/openssl-1.1.1k.conf
sudo echo '/usr/local/ssl/lib' >> /etc/ld.so.conf.d/openssl-1.1.1k.conf

## symbol link to lib64
sudo ln -s /usr/local/ssl/lib/libssl.so.1.1 /usr/lib64/libssl.so.1.1
sudo ln -s /usr/local/ssl/lib/libcrypto.so.1.1 /usr/lib64/libcrypto.so.1.1
sudo ln -s /usr/local/ssl/bin/openssl /bin/openssl

########### 2. install python ###########
cd /opt
sudo wget https://www.python.org/ftp/python/3.11.3/Python-3.11.3.tgz  --no-check-certificate
sudo tar -zxvf Python-3.11.3.tgz
cd Python-3.11.3
./configure
make
sudo make install
sudo chown $(whoami):$(whoami) /etc/profile
echo 'alias python=/usr/local/bin/python3.11' >> /etc/profile
echo 'alias python3=/usr/local/bin/python3.11' >> /etc/profile
echo 'alias pip=/usr/local/bin/pip3.11' >> /etc/profile
echo 'alias pip3=/usr/local/bin/pip3.11' >> /etc/profile
source /etc/profile

########### 3. install kubespray in venv ###########
cd ~
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
#python -m venv kubespray-venv
#source kubespray-venv/bin/activate
pip3 install -r requirements.txt

## copy kubespray k8s template (manually)
cp -rfp ~/kubespray/inventory/sample ~/kubespray/inventory/k8s-clusters
bash -c 'cat << EOF > ~/kubespray/inventory/k8s-clusters/inventory.ini
[all]
k8s-master ansible_host=192.168.1.10  ip=192.168.1.10
k8s-worker1 ansible_host=192.168.1.21  ip=192.168.1.21
k8s-worker2 ansible_host=192.168.1.22  ip=192.168.1.22
k8s-worker3 ansible_host=192.168.1.23  ip=192.168.1.23

[kube_control_plane]
k8s-master
[etcd]
k8s-master
[kube_node]
k8s-worker1
k8s-worker2
k8s-worker3
[calico_rr]
[k8s_cluster:children]
kube_control_plane
kube_node
calico_rr
EOF'

# cluster etcd variable modify
sudo sed -i 's/etcd_deployment_type: host/etcd_deployment_type: kubeadm/g' ~/kubespray/inventory/clusters/group_vars/all/etcd.yml

## establish ssh connection
cd ~
sudo yum install -y expect
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa

export WORKER_NODE_NUMBER=$1
cat << EOF > ssh_master.sh
#!/usr/bin/expect -f
spawn ssh-copy-id vagrant@192.168.1.10
expect {
    "Are you sure you want to continue connecting (yes/no" {
        send "yes\r"; exp_continue
    }
    "password:" {
        send "vagrant\r"; exp_continue
    }
}
EOF
sudo chmod +x ssh_master.sh
./ssh_master.sh

for ((i=1; i<=WORKER_NODE_NUMBER; i++))
do 
cat << EOF > ssh_worker${i}.sh
#!/usr/bin/expect -f
spawn ssh-copy-id vagrant@192.168.1.2$i
expect {
    "Are you sure you want to continue connecting (yes/no" {
        send "yes\r"; exp_continue
    }
    "password:" {
        send "vagrant\r"; exp_continue
    }
}
EOF
sudo chmod +x ssh_worker${i}.sh
./ssh_worker${i}.sh
done

# enable metric server
sudo sed -i 's/metrics_server_enabled: false/metrics_server_enabled: true/g' ~/kubespray/inventory/k8s-clusters/group_vars/k8s_cluster/addons.yml

# enable helm by kubespray template
sudo sed -i 's/helm_enabled: false/helm_enabled: true/g' ~/kubespray/inventory/k8s-clusters/group_vars/k8s_cluster/addons.yml

## run ansible-playbook
cd ~/kubespray
ansible-playbook -i ~/kubespray/inventory/k8s-clusters/inventory.ini -become --become-user=root ~/kubespray/cluster.yml 

## configuration for authorization to use kubecli command (for root user)
sudo mkdir -p /.kube
sudo cp -i /etc/kubernetes/admin.conf /.kube/config
sudo chown $(id -u):$(id -g) /root/.kube/config
# configuration for authorization to use kubecli command (for vagrant user)
sudo mkdir -p /home/vagrant/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo chown vagrant:vagrant /home/vagrant/.kube/config

# set bash-completion
sudo yum install bash-completion -y
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc

# Install Metallb
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml

# Config Metallb L2 Layer Config
sudo bash -c 'cat << EOF > metallb-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.1.50-192.168.1.100 # external-ip range
EOF'
kubectl apply -f metallb-config.yaml
