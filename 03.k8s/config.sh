#!/usr/bin/bash

# time config
sudo timedatectl set-timezone Asia/Seoul

# allow ssh login with password
time=$(date "+%Y%m%d.%H%M%S")

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

# add hosts
sudo bash -c 'cat << EOF >> /etc/hosts
192.168.1.10 k8s-master
192.168.1.21 k8s-worker1
EOF'

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

# python
sudo apt-get install python3 python3-venv pip -y

# kubespray
cd ~
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
python3 -m venv ~/path/kubespray
source ~/path/kubespray/bin/activate
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
sudo apt-get install -y expect
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa

bash -c 'cat << EOF >> ssh_expect1.sh
#!/usr/bin/expect -f
spawn ssh-copy-id vagrant@k8s-master
expect "password:"
send "yes\r"
expect "password:"
send "vagrant\r"
interact
EOF'
sudo chmod +x ssh_expect1.sh

bash -c 'cat << EOF >> ssh_expect2.sh
#!/usr/bin/expect -f
spawn ssh-copy-id vagrant@k8s-worker1
expect "password:"
send "yes\r"
expect "password:"
send "vagrant\r"
interact
EOF'
sudo chmod +x ssh_expect2.sh

exit

./ssh_expect1.sh
sleep 1
./ssh_expect2.sh

## run kubespray for install k8s
cd ~/kubespray
ansible-playbook -i ~/kubespray/inventory/k8s-clusters/inventory.ini -become --become-user=root ~/kubespray/cluster.yml 
deactivate

# configuration for authorization to use kubecli command (for vagrant user)
sudo mkdir -p /home/$(whoami)/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/$(whoami)/.kube/config
sudo chown $(whoami):$(whoami) /home/$(whoami)/.kube/config

# set bash-completion
sudo apt-get install bash-completion -y
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -F __start_kubectl k' >> ~/.bashrc

# Install Metallb
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# Config Metallb L2 Layer Config
sudo bash -c 'cat << EOF > IPAddressPool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.101-192.168.1.200 # LoadBalancer Object ip range
EOF'
kubectl apply -f IPAddressPool.yaml