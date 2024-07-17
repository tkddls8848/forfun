#!/usr/bin/bash

# add host for ssh
export WORKER_NODE_NUMBER=$1
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

for ((i=1; i<=WORKER_NODE_NUMBER; i++))
do 
cat << EOF >> ssh_worker${i}.sh
#!/usr/bin/expect -f
spawn ssh-copy-id vagrant@192.168.56.2$i
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
done

# run ssh public key copy script
sudo apt-get install -y expect
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
./ssh_master.sh
sudo rm -f ssh_master.sh
for ((i=1; i<=WORKER_NODE_NUMBER; i++))
do
./ssh_worker${i}.sh
sudo rm -f ssh_worker${i}.sh
done

# install python
sudo apt-get install python3 python3.10-venv pip -y

# install kubespray
export KUBESPRAY_VERSION='release-2.25'
cd ~
git clone -b $KUBESPRAY_VERSION https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
python3 -m venv ~/.venv/kubespray
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
sudo sed -i 's/etcd_deployment_type: host/etcd_deployment_type: kubeadm/g' ~/kubespray/inventory/clusters/group_vars/all/etcd.yml

# enable metric server
sudo sed -i 's/metrics_server_enabled: false/metrics_server_enabled: true/g' ~/kubespray/inventory/k8s-clusters/group_vars/k8s_cluster/addons.yml

# enable helm by kubespray template
sudo sed -i 's/helm_enabled: false/helm_enabled: true/g' ~/kubespray/inventory/k8s-clusters/group_vars/k8s_cluster/addons.yml

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
      - 192.168.56.150-192.168.56.250 # external-ip range
EOF'
kubectl apply -f metallb-config.yaml