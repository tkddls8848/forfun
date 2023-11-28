# time config
timedatectl set-timezone Asia/Seoul

# util install
yum -y update
yum -y install net-tools bash-completion curl wget yum-utils
modprobe overlay
modprobe br_netfilter
yum install -y iproute-tc

# docker install
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 
yum -y install docker-ce containerd.io
systemctl start docker

# container runtime (container.d)
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# disable firewall
systemctl disable firewalld
systemctl stop firewalld

# apply the 99-kubernetes-cri.conf file immediately
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system

# k8s common setup
cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

# swap disable
swapoff -a
sed -e '/swap/s/^/#/' -i /etc/fstab

# entitle hostname 
tee /etc/hosts <<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
:1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF

# enroll DNS, $1 is worker_node number from vagrantfile
for i in $1
do
    echo "192.168.55.1$i worker$i w$i" >> /etc/hosts
done
echo "192.168.55.10 master  m" >> /etc/hosts