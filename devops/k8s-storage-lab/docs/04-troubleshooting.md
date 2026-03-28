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

### SSH 타임아웃
인스턴스 부팅 미완료 또는 SG 문제. `start_k8s.sh`는 SSH 루프로 자동 대기.
수동 확인:
```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=k8s-storage-lab-*" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],State.Name,PublicIpAddress]' \
  --output table
```

---

## Kubernetes

### kube-proxy CrashLoopBackOff (exit code 2)
**원인**: Ubuntu 24.04 nftables 환경에서 kube-proxy iptables 모드 기동 시
Flannel과 `/run/xtables.lock` 경합.

**현재 구성**: `kubeadm init` 시 `KubeProxyConfiguration mode: nftables` 기본 적용으로 재발 없음.

수동 적용:
```bash
kubectl -n kube-system get configmap kube-proxy -o yaml \
  | sed 's/mode: ""/mode: "nftables"/' \
  | kubectl apply -f -
kubectl -n kube-system rollout restart daemonset kube-proxy
```

### kubeadm init 실패 (etcd context deadline)
```bash
ssh ubuntu@<master-1-ip>
sudo kubeadm reset -f
sudo rm -rf /etc/cni /etc/kubernetes /var/lib/kubelet /var/lib/etcd ~/.kube
sudo systemctl restart containerd
```
이후 `start_k8s.sh` 재실행.

### Master-2/3 control-plane join 실패 (certificate-key 만료)
kubeadm certificate-key는 2시간 유효. 만료 시:
```bash
# master-1에서
sudo kubeadm init phase upload-certs --upload-certs
# 출력된 cert-key로 재시도
sudo kubeadm join BASTION_PRIVATE_IP:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane \
  --certificate-key <NEW_CERT_KEY> \
  --node-name master-2
```

### HAProxy health check 실패 (master backend DOWN)
```bash
# bastion에서
sudo cat /etc/haproxy/haproxy.cfg
curl http://localhost:9000/stats
# 특정 master가 DOWN이면 해당 master의 kubelet 확인
ssh ubuntu@<master-ip> "sudo systemctl status kubelet"
```

### Worker join 실패 (token 만료)
```bash
# master-1에서
sudo kubeadm token create --print-join-command
```

### Flannel Pod Pending / 노드 NotReady
```bash
kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
kubectl apply  -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

---

## rook-ceph

### OSD Pod가 생성되지 않음

rbd 모듈 미로드 확인:
```bash
ssh ubuntu@<worker-ip> "lsmod | grep rbd || sudo modprobe rbd"
```

디스크에 기존 시그니처가 남아있는 경우:
```bash
bash destroy_ceph.sh && bash start_ceph.sh
```

### Ceph HEALTH_WARN TOO_FEW_OSDS
`osd_pool_default_size: "2"`에서 OSD 2개 이상이면 정상.
```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd tree
```

### rook-ceph-tools 상태 확인
```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph df
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd tree
```

---

## BeeGFS

### beegfs-mgmtd/meta Pod CrashLoopBackOff
패키지가 설치되지 않았거나 config 파일 미설정.
```bash
kubectl -n beegfs-system logs deploy/beegfs-mgmtd
# master-1에서
ls /usr/sbin/beegfs-mgmtd
cat /etc/beegfs/beegfs-mgmtd.conf | grep storeMgmt
```

### storaged DaemonSet Pod Pending (node selector 불일치)
Worker 노드에 `node-role.kubernetes.io/worker` 레이블 확인:
```bash
kubectl get nodes --show-labels | grep worker
# 레이블이 없으면
kubectl label node worker-1 node-role.kubernetes.io/worker=""
```

### BeeGFS 스토리지 디스크 마운트 실패
```bash
ssh ubuntu@<worker-ip>
lsblk                     # nvme3n1 확인
sudo blkid /dev/nvme3n1   # 파일시스템 확인
mount | grep beegfs       # 마운트 여부 확인
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
# ceph-rbd, ceph-cephfs 없으면
bash start_ceph.sh

# beegfs-scratch 없으면
bash start_beegfs.sh
```
