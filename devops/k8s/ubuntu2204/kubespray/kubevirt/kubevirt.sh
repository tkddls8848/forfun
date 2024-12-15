## **KubeVirt 최신 버전 정보 가져오기:**
export KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases/latest | grep tag_name | cut -d '"' -f 4)
## **KubeVirt Operator 설치:**
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
## **KubeVirt Custom Resource(CR) 설치:**
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml
## **KubeVirt 설치 확인:**
kubectl -n kubevirt get pods
## **virtctl 설치:**
wget https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/virtctl-${KUBEVIRT_VERSION}-linux-amd64
chmod +x virtctl-${KUBEVIRT_VERSION}-linux-amd64
sudo mv virtctl-${KUBEVIRT_VERSION}-linux-amd64 /usr/local/bin/virtctl

kubectl apply -f https://raw.githubusercontent.com/kubevirt/kubevirt.github.io/master/labs/manifests/vm.yaml
virtctl start testvm
virtctl stop testvm


## **CDI 설치**
export VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator.yaml
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-cr.yaml

kubectl create -f https://raw.githubusercontent.com/kubevirt/containerized-data-importer/$VERSION/manifests/example/import-kubevirt-datavolume.yaml









wget -O win2016.iso 'https://go.microsoft.com/fwlink/p/?LinkID=2195174&clcid=0x409&culture=en-us&country=US'




sudo virtctl image-upload \
   --image-path=$(pwd)/win2016.iso \
   --pvc-name=iso-win2016 \
   --access-mode=ReadWriteOnce \
   --size=7G \
   --uploadproxy-url=https://uploadproxy.10.10.100.10.nip.io:443 \
   --insecure \
   --wait-secs=240

kubectl apply -f -<< EOF 
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: uploadproxy-ingress
  namespace: cdi
  annotations:
    cert-manager.io/cluster-issuer: selfsigned-cluster-issuer
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  rules:
  - host: "uploadproxy.10.10.100.10.nip.io"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: cdi-uploadproxy
            port:
              number: 443
  tls:
  - hosts:
    - uploadproxy.10.10.100.10.nip.io
    secretName: uploadproxy-cert
EOF

docker pull kubevirt/virtio-container-disk

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: winhd
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 7Gi
  storageClassName: standard
---
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: iso-win2016
spec:
  running: false
  template:
    metadata:
      labels:
        kubevirt.io/domain: iso-win2016
    spec:
      domain:
        cpu:
          cores: 4
        devices:
          disks:
          - bootOrder: 1
            cdrom:
              bus: sata
            name: cdromiso
          - disk:
              bus: virtio
            name: harddrive
          - cdrom:
              bus: sata
            name: virtiocontainerdisk
        machine:
          type: q35
        resources:
          requests:
            memory: 8G
      volumes:
      - name: cdromiso
        persistentVolumeClaim:
          claimName: iso-win2016
      - name: harddrive
        persistentVolumeClaim:
          claimName: winhd
      - containerDisk:
          image: kubevirt/virtio-container-disk
        name: virtiocontainerdisk

kubectl create -f win2016.yml

virtctl start iso-win2016

kubectl get vm,vmi
##create dv volume
kubectl apply -f - <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: my-datavolume
spec:
  source:
    http:
      url: "https://example.com/path/to/virtual-machine-disk-image.qcow2"
  pvc:
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 10Gi
EOF

kubectl apply -f - << EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: my-virtualmachine
spec:
  runStrategy: true
  template:
    spec:
      domain:
        devices:
          disks:
          - disk:
              bus: virtio
            name: datavolumedisk1
        resources:
          requests:
            memory: 2Gi
      volumes:
      - dataVolume:
          name: my-datavolume
        name: datavolumedisk1
EOF


#### 1. KubeVirt 환경 준비
앞서 설명한 바와 같이, KubeVirt가 설치된 Kubernetes 클러스터가 필요합니다. 클러스터와 KubeVirt가 정상적으로 동작하고 있는지 확인한 후 예제를 시작합니다.

```bash
kubectl get pods -n kubevirt
```


kubectl apply -f https://kubevirt.io/labs/manifests/vm.yaml
virtctl console testvm

#### 2. VirtualMachineInstance 매니페스트 작성
CirrOS 이미지를 사용하는 간단한 VMI를 정의합니다. 아래는 VMI 매니페스트의 예시입니다.

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachineInstance
metadata:
  name: my-vmi
  namespace: default
spec:
  domain:
    devices:
      disks:
      - disk:
          bus: virtio
        name: containerdisk
    resources:
      requests:
        memory: 64M
  terminationGracePeriodSeconds: 0
  volumes:
  - containerDisk:
      image: kubevirt/cirros-container-disk-demo
    name: containerdisk
```

위 YAML 파일을 예를 들어 `vmi-cirros.yaml`로 저장합니다.

#### 3. VirtualMachineInstance 생성

위에서 작성한 매니페스트 파일을 적용하여 VMI를 생성합니다.

```bash
kubectl apply -f vmi-cirros.yaml
```

#### 4. VirtualMachineInstance 상태 확인

VMI의 상태를 확인하여 가상 머신이 실행되고 있는지 확인합니다.

```bash
kubectl get vmi
```

출력에서 VMI가 `Running` 상태로 나타나면 정상적으로 실행되고 있는 것입니다.

#### 5. 가상 머신 콘솔에 접근

CirrOS 가상 머신의 콘솔에 접근하여 상호작용할 수 있습니다. 다음 명령어를 사용하여 VMI 콘솔에 접속합니다.

```bash
virtctl console my-vmi
```

`virtctl`은 KubeVirt와 상호작용할 수 있도록 도와주는 CLI 도구이며, [KubeVirt GitHub](https://github.com/kubevirt/kubevirt/releases)에서 다운로드할 수 있습니다.

#### 6. VMI 삭제

가상 머신 인스턴스를 더 이상 사용하지 않으려면 다음 명령어로 삭제할 수 있습니다.

```bash
kubectl delete vmi my-vmi
```
