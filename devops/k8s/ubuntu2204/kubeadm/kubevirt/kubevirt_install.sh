#!/usr/bin/bash

## https://kmaster.tistory.com/87
## https://github.com/kubevirt/kubevirt/blob/main/docs/software-emulation.md
export KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases/latest | grep tag_name | cut -d '"' -f 4)

## install Kubevirt operator and custom resource
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml

## install Kubevirt custom resource
if egrep -c '(vmx|svm)' /proc/cpuinfo; then ## check for hardware virtualize
    kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml
else
    kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml
    kubectl -n kubevirt patch kubevirt kubevirt --type=merge --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
fi

## install virtctl
wget https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/virtctl-${KUBEVIRT_VERSION}-linux-amd64
chmod +x virtctl-${KUBEVIRT_VERSION}-linux-amd64
sudo mv virtctl-${KUBEVIRT_VERSION}-linux-amd64 /usr/local/bin/virtctl

## run test cirros OS vm
kubectl apply -f https://kubevirt.io/labs/manifests/vm.yaml
virtctl start testvm
#virtctl console testvm
virtctl stop testvm

## install Containerized Data Importer (CDI)
export CDI_VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$CDI_VERSION/cdi-operator.yaml
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$CDI_VERSION/cdi-cr.yaml
kubectl create -f https://raw.githubusercontent.com/kubevirt/containerized-data-importer/$CDI_VERSION/manifests/example/import-kubevirt-datavolume.yaml

