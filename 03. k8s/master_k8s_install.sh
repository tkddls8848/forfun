# necessary info for kubeadm network
pod_network="10.244.0.0/16"
apiserver_network=$(hostname -i)

# configure pod network and save token for cluster join
kubeadm init --pod-network-cidr=$pod_network --apiserver-advertise-address=$apiserver_network | tee /home/vagrant/kubeadm_init_output
grep -A 2 'kubeadm join' /home/vagrant/kubeadm_init_output > /home/vagrant/token

# configuration for authorization to use kubecli command (for root user)
export KUBECONFIG=/etc/kubernetes/admin.conf
echo KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# download the CNI flannel file if it is not in the current directory
[ -f kube-flannel.yml ] || wget https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# add eth1 interface card to the CNI flannel yaml file
#(This setting is neccssary if the first nic of the host is a nat type)
sed -e "/kube-subnet-mgr/a\        - --iface=eth1" kube-flannel.yml > modified-kube-flannel.yml
kubectl apply -f ./modified-kube-flannel.yml