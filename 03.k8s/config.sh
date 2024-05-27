#!/usr/bin/bash

# time config
sudo timedatectl set-timezone Asia/Seoul
time=$(date "+%Y%m%d.%H%M%S")

# install net tools
sudo apt install net-tools

# swapoff -a to disable swapping 
sudo swapoff -a
sudo sed -e '/swap/s/^/#/' -i /etc/fstab

# set SELinux disable
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
sestatus

# enabling iptables kernel options
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF
 
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl --system

# disable firewall
sudo ufw disable

# config DNS
sudo bash -c 'cat << EOF > /etc/resolv.conf
nameserver 8.8.8.8 #Google DNS
EOF'

# ssh password Authentication no to yes
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config_$time.backup
sudo sed -i -e 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo systemctl daemon-reload && sudo systemctl restart ssh

# root without password
sudo echo "vagrant ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# install nfs
sudo apt-get install nfs-common -y

# add host
export WORKER_NODE_NUMBER=$1
echo "192.168.56.10 k8s-master" | sudo tee -a /etc/hosts > /dev/null
cat << EOF >> ssh_master.sh
#!/usr/bin/expect -f
spawn ssh-copy-id vagrant@k8s-master
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
echo "192.168.56.2$i" k8s-worker${i} | sudo tee -a /etc/hosts > /dev/null
cat << EOF >> ssh_worker${i}.sh
#!/usr/bin/expect -f
spawn ssh-copy-id vagrant@k8s-worker${i}
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
export KUBESPRAY_VERSION='release-2.23'
cd ~
git clone -b $KUBESPRAY_VERSION https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
python3 -m venv ~/.venv/kubespray
source ~/.venv/kubespray/bin/activate
pip3 install -r requirements.txt

# generate ansible inventory yaml file
cp -rfp ~/kubespray/inventory/sample ~/kubespray/inventory/k8s-clusters
sed -i 's/kube_network_plugin: calico/kube_network_plugin: flannel/g' inventory/k8s-clusters/group_vars/k8s_cluster/k8s-cluster.yml
bash -c 'cat << EOF > ~/kubespray/inventory/k8s-clusters/inventory.ini
[all]
k8s-master ansible_host=192.168.56.10  ip=192.168.56.10  etcd_member_name=etcd1
k8s-worker1 ansible_host=192.168.56.21  ip=192.168.56.21
k8s-worker2 ansible_host=192.168.56.22  ip=192.168.56.22
k8s-nfs ansible_host=192.168.56.100  ip=192.168.56.100

# ## configure a bastion host if your nodes are not directly reachable
# [bastion]
# bastion ansible_host=192.168.56.31 ansible_user=vagrant

[kube_control_plane]
k8s-master

[etcd]
k8s-master

[kube_node]
k8s-worker1
k8s-worker2

[k8s_cluster:children]
kube_control_plane
kube_node
EOF'

# enable Metallb by kubespray template
sudo sed -i '/# MetalLB deployment/,+63d' ~/kubespray/inventory/k8s-clusters/group_vars/k8s_cluster/addons.yml
bash -c 'cat << EOF >> ~/kubespray/inventory/k8s-clusters/group_vars/k8s_cluster/addons.yml
metallb_enabled: true
metallb_speaker_enabled: true
metallb_namespace: "metallb-system"
metallb_ip_range:
  - "192.168.56.101-192.168.56.150"
metallb_protocol: "layer2"
metallb_pool_name: "loadbalanced"
EOF'
sudo sed -i 's/kube_proxy_strict_arp: false/kube_proxy_strict_arp: true/g' ~/kubespray/inventory/k8s-clusters/group_vars/k8s_cluster/k8s-cluster.yml

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
# kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# # enable strict ARP mode
# kubectl get configmap kube-proxy -n kube-system -o yaml | \
# sed -e "s/strictARP: false/strictARP: true/" | \
# kubectl apply -f - -n kube-system

# # Config Metallb L2 Layer Config
# touch metallbconfig.yaml
# cat << EOF > metallbconfig.yaml
# apiVersion: metallb.io/v1beta1
# kind: IPAddressPool
# metadata:
#   name: my-pool
#   namespace: metallb-system
# spec:
#   addresses:
#   - 192.168.56.101-192.168.56.150 # LoadBalancer Object ip range
# ---
# apiVersion: metallb.io/v1beta1
# kind: L2Advertisement
# metadata:
#   name: l2advertisement
#   namespace: metallb-system
# spec:
#   ipAddressPools:
#   - my-pool
# EOF

# # delete webhook
# kubectl delete validatingwebhookconfigurations metallb-webhook-configuration
# kubectl apply -f metallbconfig.yaml