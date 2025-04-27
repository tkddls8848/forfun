#!/usr/bin/bash

# 환경 변수 설정
export WORKER_NODE_NUMBER=$1
export KUBESPRAY_VERSION='release-2.26'
export KUBESPRAY_HOME="$HOME/kubespray"
export VENV_PATH="$HOME/.venv/kubespray"

# 필수 패키지 설치
sudo apt-get update && sudo apt-get install -y expect python3.11 python3.11-venv pip bash-completion

# SSH 키 설정
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# SSH 키 복사 함수
copy_ssh_key() {
    local host=$1
    local user=$2
    local password=$3
    
    expect << EOF
spawn ssh-copy-id $user@$host
expect {
    "Are you sure you want to continue connecting" {
        send "yes\r"
        exp_continue
    }
    "password:" {
        send "$password\r"
        exp_continue
    }
}
expect eof
EOF
}

# 마스터 노드에 SSH 키 복사
copy_ssh_key "192.168.56.10" "vagrant" "vagrant"

# 워커 노드에 SSH 키 복사
for ((i=1; i<=WORKER_NODE_NUMBER; i++))
do 
    copy_ssh_key "192.168.56.2$i" "vagrant" "vagrant"
done

# Kubespray 설치
cd ~
git clone -b $KUBESPRAY_VERSION https://github.com/kubernetes-sigs/kubespray.git
cd $KUBESPRAY_HOME

# Python 가상환경 설정
python3.11 -m venv $VENV_PATH
source $VENV_PATH/bin/activate
pip3 install -r requirements.txt

# 인벤토리 파일 생성
cp -rfp $KUBESPRAY_HOME/inventory/sample $KUBESPRAY_HOME/inventory/k8s-clusters

cat > $KUBESPRAY_HOME/inventory/k8s-clusters/inventory.ini << EOF
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
EOF

# etcd 설정
cat > $KUBESPRAY_HOME/inventory/k8s-clusters/group_vars/all/etcd.yml << EOF
etcd_kubeadm_enabled: true
EOF

# 메트릭 서버 및 Helm 활성화
sed -i 's/metrics_server_enabled: false/metrics_server_enabled: true/g' $KUBESPRAY_HOME/inventory/k8s-clusters/group_vars/k8s_cluster/addons.yml
sed -i 's/helm_enabled: false/helm_enabled: true/g' $KUBESPRAY_HOME/inventory/k8s-clusters/group_vars/k8s_cluster/addons.yml

# 클러스터 배포
cd $KUBESPRAY_HOME
ansible-playbook -i $KUBESPRAY_HOME/inventory/k8s-clusters/inventory.ini -become --become-user=root $KUBESPRAY_HOME/cluster.yml
deactivate

# kubectl 설정
sudo mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# bash-completion 설정
echo 'source <(kubectl completion bash)' >> ~/.bashrc

# MetalLB 설치
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl apply -f - -n kube-system

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.7/config/manifests/metallb-native.yaml

cat > metallb-pool.yaml << EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lb-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.56.128/28
EOF

# MetalLB LoadBalancer가 Active 상태가 될 때까지 대기
echo "Waiting for LoadBalancer to be ready..."
while true; do
    ready_metallb=$(kubectl get ns metallb-system --no-headers | awk '{print $2}')
    if [ "$ready_metallb" = "Active" ]; then
        echo "All nodes are ready"
        kubectl apply -f metallb-pool.yaml
        break
    fi
    echo "Waiting for MetalLB LoadBalancer to be ready... Current MetalLB LoadBalancer status: $ready_metallb"
    sleep 10
done
