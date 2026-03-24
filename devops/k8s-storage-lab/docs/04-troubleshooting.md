# 04. 트러블슈팅

---

## 인프라 (OpenTofu)

### `tofu apply` 시 Key Pair 오류
```
Error: InvalidKeyPair.NotFound
```
`terraform.tfvars`의 `key_name`이 해당 리전에 없음.
```bash
aws ec2 describe-key-pairs --region ap-northeast-2 --query 'KeyPairs[].KeyName'
```

### user_data 실행 실패
```bash
ssh -i ~/.ssh/storage-lab.pem ubuntu@<ip>
sudo cat /var/log/cloud-init-output.log
```

---

## SSH / 부팅

### SSH 타임아웃 (00_hosts_setup.sh)
인스턴스 부팅 미완료 또는 SG 문제. `start_k8s.sh`는 60초 대기 후 SSH 루프를 돌며 자동 대기.
수동 확인:
```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=k8s-storage-lab-*" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],State.Name,PublicIpAddress]' \
  --output table
```

### cloud-init 완료 후에도 K8s 설치 실패
user_data에서 reboot 발생 시 cloud-init 상태가 "running"으로 유지될 수 있음.
`01_k8s_install.sh`의 SSH 재연결 루프가 처리함. 수동 확인:
```bash
ssh ubuntu@<ip> "cloud-init status"
```

---

## Kubernetes

### kube-proxy CrashLoopBackOff (exit code 2)
**원인**: Ubuntu 24.04 nftables 환경에서 kube-proxy iptables 모드 기동 시
Flannel과 `/run/xtables.lock` 경합 → 클러스터 네트워킹 붕괴.

**현재 구성**: `01_k8s_install.sh`에서 `KubeProxyConfiguration mode: nftables`를 기본 적용하므로 재발하지 않음.

기동 중인 클러스터에 수동 적용:
```bash
kubectl -n kube-system get configmap kube-proxy -o yaml \
  | sed 's/mode: ""/mode: "nftables"/' \
  | kubectl apply -f -
kubectl -n kube-system rollout restart daemonset kube-proxy
```

### API server 응답 없음 (connection refused)
```bash
ssh -i ~/.ssh/storage-lab.pem ubuntu@<master-ip> \
  "sudo systemctl restart kubelet"
```

### kubeadm init 실패 (etcd context deadline)
containerd 미실행 또는 cloud-init 미완료 상태에서 init 시도.
`01_k8s_install.sh`는 cloud-init 완료 대기 후 설치 진행.

수동 재설치:
```bash
ssh ubuntu@<master-ip>
sudo kubeadm reset -f
sudo rm -rf /etc/cni /etc/kubernetes /var/lib/kubelet /var/lib/etcd ~/.kube
sudo systemctl restart containerd
# 로컬에서
bash scripts/01_k8s_install.sh
```

### Flannel Pod Pending / 노드 NotReady
```bash
kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
kubectl apply  -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

### Worker join 실패 (token 만료)
```bash
ssh ubuntu@<master-ip> "sudo kubeadm token create --print-join-command"
```

---

## rook-ceph

### OSD Pod가 생성되지 않음

rbd 모듈 미로드 확인:
```bash
ssh ubuntu@<worker-ip> "lsmod | grep rbd"
# 없으면
ssh ubuntu@<worker-ip> "sudo modprobe rbd"
```

디스크에 기존 파티션/시그니처가 남아있는 경우:
```bash
# destroy_ceph.sh 실행 후 재설치
bash destroy_ceph.sh && bash start_ceph.sh
```

### Ceph HEALTH_WARN TOO_FEW_OSDS
`osd_pool_default_size`가 실제 OSD 수보다 크면 발생.
현재 구성(`osd_pool_default_size: "2"`, replication `size: 2`)에서는 OSD 4개 이상이면 정상.

### rook-ceph-tools에서 확인
```bash
export KUBECONFIG=~/.kube/config-k8s-storage-lab
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd tree
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph df
```

### rook-ceph 재설치
```bash
bash destroy_ceph.sh
bash start_ceph.sh
```

---

## GPFS

### `mmbuildgpl` 실패 (커널 헤더 불일치)
```bash
uname -r
dpkg -l | grep linux-headers
sudo apt-get install -y linux-headers-$(uname -r)
sudo /usr/lpp/mmfs/bin/mmbuildgpl
```

### NSD 디스크 인식 실패
Nitro 기반 인스턴스에서 `/dev/nvme*`로 표시될 수 있음.
```bash
lsblk
ls /dev/xvd* /dev/nvme* 2>/dev/null
```

### mmstartup 후 노드 미활성
```bash
sudo /usr/lpp/mmfs/bin/mmgetstate -a
sudo tail -100 /var/mmfs/gen/mmfslog
```

---

## PVC / CSI

### PVC Pending 상태 지속
```bash
kubectl describe pvc <pvc-name>
kubectl logs -n rook-ceph deploy/rook-ceph-operator | tail -50
```

### StorageClass 없음
```bash
kubectl get storageclass
# ceph-rbd, ceph-cephfs 없으면 02_ceph_install.sh 재실행
bash start_ceph.sh
```
