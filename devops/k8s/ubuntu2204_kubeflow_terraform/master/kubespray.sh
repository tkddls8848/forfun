#!/usr/bin/bash

# add host for ssh
cat << EOF >> ssh_master.sh
#!/usr/bin/expect -f
spawn ssh-copy-id vagrant@192.168.55.10
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

cat << EOF >> ssh_worker1.sh
#!/usr/bin/expect -f
spawn ssh-copy-id vagrant@192.168.55.21
expect {
    "Are you sure you want to continue connecting (yes/no" {
        send "yes\r"; exp_continue
    }
    "password:" {
        send "vagrant\r"; exp_continue
    }
}
EOF
sudo chmod +x ssh_worker1.sh

# run ssh public key copy script
sudo apt-get install -y expect
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
./ssh_master.sh
./ssh_worker1.sh


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
cp -rfp ~/kubespray/inventory/sample ~/kubespray/inventory/clusters
sed -i 's/kube_network_plugin: calico/kube_network_plugin: flannel/g' inventory/clusters/group_vars/k8s_cluster/cluster.yml
bash -c 'cat << EOF > ~/kubespray/inventory/clusters/inventory.ini
[all]
master ansible_host=192.168.55.10  ip=192.168.55.10
worker1 ansible_host=192.168.55.21  ip=192.168.55.21

[kube_control_plane]
master

[kube_node]
worker1

[etcd]
master

[k8s_cluster:children]
kube_control_plane
kube_node
EOF'

# cluster etcd variable modify
sudo sed -i 's/etcd_deployment_type: host/etcd_deployment_type: kubeadm/g' ~/kubespray/inventory/clusters/group_vars/all/etcd.yml

# enable Metallb by kubespray template
sudo sed -i '/# MetalLB deployment/,+63d' ~/kubespray/inventory/clusters/group_vars/k8s_cluster/addons.yml
bash -c 'cat << EOF >> ~/kubespray/inventory/clusters/group_vars/k8s_cluster/addons.yml
metallb_enabled: true
metallb_speaker_enabled: true
metallb_namespace: "metallb-system"
metallb_ip_range:
  - "192.168.55.150-192.168.55.200"
metallb_protocol: "layer2"
metallb_pool_name: "loadbalanced"
EOF'
sudo sed -i 's/kube_proxy_strict_arp: false/kube_proxy_strict_arp: true/g' ~/kubespray/inventory/clusters/group_vars/k8s_cluster/k8s-cluster.yml

# cluster addon variable modify
sudo sed -i 's/metrics_server_enabled: false/metrics_server_enabled: true/g' ~/kubespray/inventory/k8s-clusters/group_vars/k8s_cluster/addons.yml
sudo sed -i 's/ingress_nginx_enabled: false/ingress_nginx_enabled: true/g' ~/kubespray/inventory/k8s-clusters/group_vars/k8s_cluster/addons.yml
sudo sed -i 's/helm_enabled: false/helm_enabled: true/g' ~/kubespray/inventory/clusters/group_vars/k8s_cluster/addons.yml

# execute ansible-playbook cluster.yml file
cd ~/kubespray
ansible-playbook -i ~/kubespray/inventory/clusters/inventory.ini -become --become-user=root ~/kubespray/cluster.yml 
deactivate

# configuration for authorization to use kubecli command in master node (for vagrant user)
sudo mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# set bash-completion
sudo apt-get install bash-completion -y
echo 'source <(kubectl completion bash)' >> ~/.bashrc