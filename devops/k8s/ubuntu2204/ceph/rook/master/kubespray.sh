#!/usr/bin/bash

# add host for ssh
export WORKER_NODE_NUMBER=$1
sudo apt-get install -y expect
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

cat << EOF >> ssh_master.sh
#!/usr/bin/expect -f
spawn ssh-copy-id vagrant@192.168.56.10
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
sudo rm ssh_master.sh

for ((i=1; i<=WORKER_NODE_NUMBER; i++))
do 
cat << EOF >> ssh_worker${i}.sh
#!/usr/bin/expect -f
spawn ssh-copy-id vagrant@192.168.56.2$i
expect {
    "Are you sure you want to continue connecting" {
        send "yes\r"; exp_continue
    }
    "password:" {
        send "vagrant\r"; exp_continue
    }
}
EOF
sudo chmod +x ssh_worker${i}.sh
./ssh_worker${i}.sh
sudo rm ssh_worker${i}.sh
done

# install python
sudo apt-get install python3.11 python3.11-venv pip -y

# install kubespray
export KUBESPRAY_VERSION='release-2.26'
cd ~
git clone -b $KUBESPRAY_VERSION https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
python3.11 -m venv ~/.venv/kubespray
source ~/.venv/kubespray/bin/activate
pip3 install -r requirements.txt

# generate ansible inventory yaml file
cp -rfp ~/kubespray/inventory/sample ~/kubespray/inventory/k8s-clusters
bash -c 'cat << EOF > ~/kubespray/inventory/k8s-clusters/inventory.ini
[all]
k8s-master ansible_host=192.168.56.10  ip=192.168.56.10
k8s-worker1 ansible_host=192.168.56.21  ip=192.168.56.21
k8s-worker2 ansible_host=192.168.56.22  ip=192.168.56.22
k8s-worker3 ansible_host=192.168.56.23  ip=192.168.56.23

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
EOF'

# cluster etcd variable modify
sed -i 's/etcd_deployment_type: host/etcd_deployment_type: kubeadm/g' ~/kubespray/inventory/k8s-clusters/group_vars/all/etcd.yml
bash -c 'cat << EOF > ~/kubespray/inventory/k8s-clusters/group_vars/all/etcd.yml
etcd_kubeadm_enabled: true
EOF'

# enable metric server
sed -i 's/metrics_server_enabled: false/metrics_server_enabled: true/g' ~/kubespray/inventory/k8s-clusters/group_vars/k8s_cluster/addons.yml

# enable helm by kubespray template
sed -i 's/helm_enabled: false/helm_enabled: true/g' ~/kubespray/inventory/k8s-clusters/group_vars/k8s_cluster/addons.yml

# execute ansible-playbook cluster.yml file
cd ~/kubespray
ansible-playbook -i ~/kubespray/inventory/k8s-clusters/inventory.ini -become --become-user=root ~/kubespray/cluster.yml 
deactivate

# configuration for authorization to use kubecli command in master node (for vagrant user)
sudo mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# set bash-completion
sudo apt-get install bash-completion -y
echo 'source <(kubectl completion bash)' >> ~/.bashrc

## Install Metallb
cd ~

kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl diff -f - -n kube-system

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.7/config/manifests/metallb-native.yaml

sudo bash -c 'cat << EOF > metallb-pool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lb-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.56.128/28
EOF'
kubectl apply -f metallb-pool.yaml