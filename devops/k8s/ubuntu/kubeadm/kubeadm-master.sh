#!/bin/bash
#=========================================================================
# Kubernetes 마스터 노드 설정 스크립트
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

MASTER_IP=$1
POD_CIDR=$2
NETWORK_PREFIX=$3
WORKER_LENGTH=$4
KUBE_VERSION=$5
CALICO_VERSION=$6
echo $MASTER_IP $POD_CIDR $NETWORK_PREFIX $WORKER_LENGTH $KUBE_VERSION $CALICO_VERSION

#=========================================================================
# 1. Kubernetes 컨트롤 플레인 초기화
#=========================================================================
echo -e "\n[단계 1/5] Kubernetes 컨트롤 플레인 초기화를 시작합니다..."

# kubelet 이미지 사전 다운로드 
echo ">> kubelet 이미지 다운로드 중..."
kubeadm config images pull --kubernetes-version=$KUBE_VERSION

# SSH 접속을 위한 expect 패키지만 설치 (SSH 설정 변경은 제거)
echo ">> expect 패키지 설치 중..."
sudo apt-get install -y expect

# 클러스터 초기화
echo ">> 클러스터 초기화 중..."
kubeadm init --apiserver-advertise-address=$MASTER_IP --pod-network-cidr=$POD_CIDR --kubernetes-version=$KUBE_VERSION

#=========================================================================
# 2. kubectl 설정
#=========================================================================
echo -e "\n[단계 2/5] kubectl 설정을 시작합니다..."

echo ">> vagrant 사용자용 kubectl 설정 중..."
mkdir -p /home/vagrant/.kube
cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube

echo ">> root 사용자용 kubectl 설정 중..."
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

#=========================================================================
# 3. Calico CNI 설치
#=========================================================================
echo -e "\n[단계 3/5] Calico CNI 설치를 시작합니다..."

# Pod CIDR 설정을 위한 calico.yaml 다운로드 및 수정
echo ">> Calico 매니페스트 다운로드 중..."
curl -o /tmp/calico.yaml https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml

# 기본 CIDR(192.168.0.0/16)을 kubeadm 설정과 일치하도록 변경
echo ">> Pod CIDR 설정 수정 중..."
sed -i "s|192.168.0.0/16|$POD_CIDR|g" /tmp/calico.yaml

# 수정된 매니페스트 적용
echo ">> Calico CNI 배포 중..."
kubectl apply -f /tmp/calico.yaml

#=========================================================================
# 4. 워커 노드 조인 설정
#=========================================================================
echo -e "\n[단계 4/5] 워커 노드 조인 설정을 시작합니다..."

# 워커 노드가 접속할 수 있도록 조인 명령어 저장
echo ">> 조인 명령어 생성 중..."
JOIN_COMMAND=$(kubeadm token create --print-join-command)
echo "$JOIN_COMMAND" > /home/vagrant/join-command.sh
chmod 755 /home/vagrant/join-command.sh
chown vagrant:vagrant /home/vagrant/join-command.sh

#=========================================================================
# 5. 워커 노드 조인
#=========================================================================
echo -e "\n[단계 5/5] 워커 노드 조인을 시작합니다..."

# join-command.sh 파일에서 명령어 읽기
JOIN_CMD=$(cat /home/vagrant/join-command.sh)

for i in $(seq 1 "$WORKER_LENGTH"); do
    WORKER_IP="${NETWORK_PREFIX}.$((i + 10))"
    WORKER_HOSTNAME="k8s-worker-$i"
    echo ">> 워커 노드 $WORKER_HOSTNAME (IP: $WORKER_IP)에 조인 중..."
    
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
    echo ">> 워커 노드 $WORKER_HOSTNAME 조인 완료"
    echo ">> 5초 대기 후 다음 노드 처리..."
    sleep 5
done

echo ">> 모든 워커 노드 조인 완료. 노드 상태 확인 중..."
kubectl get nodes

echo -e "\n[완료] Kubernetes 마스터 노드 설정이 완료되었습니다."