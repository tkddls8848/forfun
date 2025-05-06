#!/usr/bin/bash

# KubeVirt 버전 확인
export KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases/latest | grep tag_name | cut -d '"' -f 4)

# KubeVirt 설치
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml

# virtctl 설치
wget https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/virtctl-${KUBEVIRT_VERSION}-linux-amd64
chmod +x virtctl-${KUBEVIRT_VERSION}-linux-amd64
sudo mv virtctl-${KUBEVIRT_VERSION}-linux-amd64 /usr/local/bin/virtctl

# KubeVirt 상태 확인
echo "KubeVirt 설치 상태 확인 중..."
#kubectl -n kubevirt wait --for=condition=Available --timeout=300s deployment/virt-operator
#kubectl -n kubevirt wait --for=condition=Available --timeout=300s deployment/virt-api
#kubectl -n kubevirt wait --for=condition=Available --timeout=300s deployment/virt-controller 