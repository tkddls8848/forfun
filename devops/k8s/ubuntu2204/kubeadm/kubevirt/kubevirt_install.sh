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

wget -O fedora38.qcow2 --limit-rate 10M 'https://download.fedoraproject.org/pub/fedora/linux/releases/38/Cloud/x86_64/images/Fedora-Cloud-Base-38-1.6.x86_64.qcow2'
sudo chmod 644 ./fedora38.qcow2

bash -c 'cat << EOF > sc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: no-provisioner-storage-class
provisioner: kubernetes.io/no-provisioner
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF'

## ssh k8s-worker1 => mkdir /tmp/data
bash -c 'cat << EOF > volume.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: hostpath
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  hostPath:
    path: "/tmp/data"
  storageClassName: "no-provisioner-storage-class"
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - k8s-worker1
---  
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hostpath-claim
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: "no-provisioner-storage-class"
  resources:
    requests:
      storage: 10Gi
EOF'

bash -c 'cat << EOF > vmi.yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachineInstance
metadata:
  name: testvmi-pvc
  finalizers:
  - kubevirt.io/foregroundDeleteVirtualMachine
spec:
  domain:
    resources:
      requests:
        memory: 1Gi
    devices:
      disks:
        - name: mypvcdisk
          disk: {}
  volumes:
    - name: mypvcdisk
      persistentVolumeClaim:
        claimName: hostpath-claim
EOF'

bash -c 'cat <<EOF > svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: testvmi-service
spec:
  type: NodePort
  ports:
    - port: 22        # VMI에서 열려 있는 SSH 포트
      targetPort: 22
      nodePort: 30022 # 클러스터 외부 접근을 위한 포트
  selector:
    kubevirt.io/domain: testvmi-pvc
EOF'
