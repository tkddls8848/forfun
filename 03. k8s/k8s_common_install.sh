# time config
timedatectl set-timezone Asia/Seoul

# util install
sudo yum -y update
sudo yum -y install net-tools bash-completion curl wget yum-utils device-mapper-persistent-data lvm2
sudo modprobe overlay
sudo modprobe br_netfilter
sudo yum install -y iproute-tc

# docker install
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 
sudo yum -y install docker-ce containerd.io
sudo systemctl start docker

# container runtime (container.d)
sudo mkdir -p /etc/containerd
sudo containerd config default | tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# disable firewall
sudo systemctl disable firewalld
sudo systemctl stop firewalld

# apply the 99-kubernetes-cri.conf file immediately
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system

# k8s common setup
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF
sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

# swap disable
swapoff -a
sed -e '/swap/s/^/#/' -i /etc/fstab

# entitle hostname 
sudo tee /etc/hosts <<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
:1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF
echo "192.168.55.10 master  m" >> /etc/hosts
echo "192.168.55.11 worker1 w1" >> /etc/hosts
echo "192.168.55.12 worker2 w2" >> /etc/hosts