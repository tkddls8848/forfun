#!/bin/bash

set -e

MASTER_IP=$1
POD_CIDR=$2
NETWORK_PREFIX=$3
WORKER_LENGTH=$4
echo $MASTER_IP $POD_CIDR $NETWORK_PREFIX $WORKER_LENGTH

# kubelet 이미지 사전 다운로드 
kubeadm config images pull --kubernetes-version=v1.31.0

# SSH 접속 편의를 위한 설정 - 워커 노드에 SSH 설정 수정 명령 실행
sudo apt-get install -y expect
for i in $(seq 1 "$WORKER_LENGTH"); do
    WORKER_IP="${NETWORK_PREFIX}.$((i + 10))"
    WORKER_HOSTNAME="k8s-worker-$i"
    echo "워커 노드 $WORKER_HOSTNAME (IP: $WORKER_IP)에 SSH 비밀번호 인증 활성화 중..."
    
    # Expect 스크립트를 통해 SSH 비밀번호 인증 활성화
    sudo -u vagrant expect <<EOF
set timeout 60
spawn ssh -o StrictHostKeyChecking=no vagrant@${WORKER_IP} "sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config && sudo systemctl restart sshd"
expect {
    "password:" { 
        send "vagrant\r"
        exp_continue 
    }
    eof
}
wait
EOF
    
    echo "워커 노드 $WORKER_HOSTNAME SSH 설정 완료. 5초 대기 중..."
    sleep 5
done

# 클러스터 초기화
kubeadm init --apiserver-advertise-address=$MASTER_IP --pod-network-cidr=$POD_CIDR --kubernetes-version=v1.31.0

# kubectl 설정
mkdir -p /home/vagrant/.kube
cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

# Calico CNI 설치 (3.27 버전, 간소화된 방식)
echo "Calico CNI 설치 중..."

# Pod CIDR 설정을 위한 calico.yaml 다운로드 및 수정
curl -o /tmp/calico.yaml https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# 기본 CIDR(192.168.0.0/16)을 kubeadm 설정과 일치하도록 변경
sed -i "s|192.168.0.0/16|$POD_CIDR|g" /tmp/calico.yaml

# 수정된 매니페스트 적용
kubectl apply -f /tmp/calico.yaml

# 워커 노드가 접속할 수 있도록 조인 명령어 저장
JOIN_COMMAND=$(kubeadm token create --print-join-command)
echo "$JOIN_COMMAND" > /home/vagrant/join-command.sh
chmod 755 /home/vagrant/join-command.sh
chown vagrant:vagrant /home/vagrant/join-command.sh

# 워커 노드에 SSH로 접속하여 join 명령어 실행
echo "워커 노드에 join 명령어 전송 중..."

# join-command.sh 파일에서 명령어 읽기
JOIN_CMD=$(cat /home/vagrant/join-command.sh)

for i in $(seq 1 "$WORKER_LENGTH"); do
    WORKER_IP="${NETWORK_PREFIX}.$((i + 10))"
    WORKER_HOSTNAME="k8s-worker-$i"
    echo "워커 노드 $WORKER_HOSTNAME (IP: $WORKER_IP)에 join 명령어 실행 중..."
    
    # Expect 스크립트를 통해 패스워드 자동 입력 - 타임아웃 추가
    sudo -u vagrant expect <<EOF
# 조인 명령 완료를 기다리기 위한 타임아웃 설정 (300초 = 5분)
set timeout 300
spawn ssh -o StrictHostKeyChecking=no vagrant@${WORKER_IP} "sudo ${JOIN_CMD}"
expect {
    "password:" { 
        send "vagrant\r"
        exp_continue 
    }
    eof
}
# expect 스크립트 종료 기다리기
wait
EOF
    
    # 이전 명령이 완료될 때까지 기다린 후, 다음 노드로 진행
    echo "워커 노드 $WORKER_HOSTNAME 조인 명령 완료. 5초 대기 후 다음 노드 처리..."
    sleep 5
done
kubectl get nodes

echo "마지막 워커 노드 조인 완료. 5초 대기 후 다음 작업 처리..."
sleep 5
kubectl get node