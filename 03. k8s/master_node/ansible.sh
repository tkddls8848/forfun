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

## copy kubespray k8s template
cp -rfp ~/kubespray/inventory/sample ~/kubespray/inventory/k8s-clusters
bash -c 'cat << EOF > ~/kubespray/inventory/k8s-clusters/inventory.ini
[all]
k8s-master ansible_host=192.168.1.10  ip=192.168.1.10  etcd_member_name=etcd1
k8s-worker1 ansible_host=192.168.1.21  ip=192.168.1.21
# ## configure a bastion host if your nodes are not directly reachable
# [bastion]
# bastion ansible_host=x.x.x.x ansible_user=some_user
[kube_control_plane]
k8s-master
[etcd]
k8s-master
[kube_node]
k8s-worker1
[calico_rr]
[k8s_cluster:children]
kube_control_plane
kube_node
calico_rr
EOF'

## establish ssh connection
cd ~
sudo yum install -y expect
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
bash -c 'cat << EOF >> ssh_expect1.sh
    /usr/bin/expect <<EOE
    set prompt "#"
    spawn bash -c "ssh-copy-id vagrant@k8s-master"
    expect {
      "yes/no" { send "yes\r"; exp_continue}
      (yes/no) { send "yes\r"; exp_continue}
      -nocase "password" {send "vagrant\r"; exp_continue }
      $prompt
    }
    EOE
EOF'
sudo chmod +x ssh_expect1.sh
./ssh_expect1.sh

bash -c 'cat << EOF >> ssh_expect2.sh
    /usr/bin/expect <<EOE
    set prompt "#"
    spawn bash -c "ssh-copy-id vagrant@k8s-worker1"
    expect {
      "yes/no" { send "yes\r"; exp_continue}
      (yes/no) { send "yes\r"; exp_continue}
      -nocase "password" {send "vagrant\r"; exp_continue }
      $prompt
    }
    EOE
EOF'
sudo chmod +x ssh_expect2.sh
./ssh_expect2.sh

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

