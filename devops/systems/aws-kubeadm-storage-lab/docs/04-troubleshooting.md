# 04. ?¸ëŸ¬ë¸”ìŠˆ??
---

## ?¸í”„??(OpenTofu)

### `tofu apply` ??Key Pair ?¤ë¥˜
```
Error: InvalidKeyPair.NotFound
```
`terraform.tfvars`??`key_name`???´ë‹¹ ë¦¬ì „???†ìŒ.
```bash
aws ec2 describe-key-pairs --region ap-northeast-2 --query 'KeyPairs[].KeyName'
```

### user_data ?¤í–‰ ?¤íŒ¨
```bash
ssh -i ~/.ssh/storage-lab.pem ubuntu@<ip>
sudo cat /var/log/cloud-init-output.log
```

---

## SSH / ë¶€??
### SSH ?€?„ì•„???¸ìŠ¤?´ìŠ¤ ë¶€??ë¯¸ì™„ë£??ëŠ” SG ë¬¸ì œ. `start_k8s.sh`??SSH ë£¨í”„ë¡??ë™ ?€ê¸?
?˜ë™ ?•ì¸:
```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=k8s-storage-lab-*" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],State.Name,PublicIpAddress]' \
  --output table
```

---

## Kubernetes

### kube-proxy CrashLoopBackOff (exit code 2)
**?ì¸**: Ubuntu 24.04 nftables ?˜ê²½?ì„œ kube-proxy iptables ëª¨ë“œ ê¸°ë™ ??Flannelê³?`/run/xtables.lock` ê²½í•©.

**?„ì¬ êµ¬ì„±**: `kubeadm init` ??`KubeProxyConfiguration mode: nftables` ê¸°ë³¸ ?ìš©?¼ë¡œ ?¬ë°œ ?†ìŒ.

?˜ë™ ?ìš©:
```bash
kubectl -n kube-system get configmap kube-proxy -o yaml \
  | sed 's/mode: ""/mode: "nftables"/' \
  | kubectl apply -f -
kubectl -n kube-system rollout restart daemonset kube-proxy
```

### kubeadm init ?¤íŒ¨ (etcd context deadline)
```bash
ssh ubuntu@<master-1-ip>
sudo kubeadm reset -f
sudo rm -rf /etc/cni /etc/kubernetes /var/lib/kubelet /var/lib/etcd ~/.kube
sudo systemctl restart containerd
```
?´í›„ `start_k8s.sh` ?¬ì‹¤??

### Master-2/3 control-plane join ?¤íŒ¨ (certificate-key ë§Œë£Œ)
kubeadm certificate-key??2?œê°„ ? íš¨. ë§Œë£Œ ??
```bash
# master-1?ì„œ
sudo kubeadm init phase upload-certs --upload-certs
# ì¶œë ¥??cert-keyë¡??¬ì‹œ??sudo kubeadm join BASTION_PRIVATE_IP:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane \
  --certificate-key <NEW_CERT_KEY> \
  --node-name master-2
```

### HAProxy health check ?¤íŒ¨ (master backend DOWN)
```bash
# bastion?ì„œ
sudo cat /etc/haproxy/haproxy.cfg
curl http://localhost:9000/stats
# ?¹ì • masterê°€ DOWN?´ë©´ ?´ë‹¹ master??kubelet ?•ì¸
ssh ubuntu@<master-ip> "sudo systemctl status kubelet"
```

### Worker join ?¤íŒ¨ (token ë§Œë£Œ)
```bash
# master-1?ì„œ
sudo kubeadm token create --print-join-command
```

### Flannel Pod Pending / ?¸ë“œ NotReady
```bash
VER=v0.26.1
kubectl delete -f https://github.com/flannel-io/flannel/releases/download/${VER}/kube-flannel.yml
kubectl apply  -f https://github.com/flannel-io/flannel/releases/download/${VER}/kube-flannel.yml
```

### Worker ì»¤ë„ ê³ ì • ?¤íŒ¨ (NotReady, SSH ê±°ì ˆ)
kernel_pin.yml reboot ??ë³µêµ¬ ?€?„ì•„??
```bash
# EC2 ê°•ì œ ?¬ì‹œ??INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=private-ip-address,Values=<worker-ip>" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
aws ec2 reboot-instances --instance-ids $INSTANCE_ID

# ë³µêµ¬ ?€ê¸?until ssh -o ConnectTimeout=5 <worker-name> "uname -r" 2>/dev/null; do
  echo "waiting..."; sleep 10
done
# ?´í›„ start_beegfs.sh ?¬ì‹¤??(?´ë? 6.8?´ë©´ pin ?¤í‚µ)
```

---

## rook-ceph

### OSD Podê°€ ?ì„±?˜ì? ?ŠìŒ

rbd ëª¨ë“ˆ ë¯¸ë¡œ???•ì¸:
```bash
ssh ubuntu@<worker-ip> "lsmod | grep rbd || sudo modprobe rbd"
```

?”ìŠ¤?¬ì— ê¸°ì¡´ ?œê·¸?ˆì²˜ê°€ ?¨ì•„?ˆëŠ” ê²½ìš°:
```bash
bash scripts/lifecycle/destroy_ceph.sh && bash scripts/lifecycle/start_ceph.sh
```

### Ceph HEALTH_WARN TOO_FEW_OSDS
`osd_pool_default_size: "2"`?ì„œ OSD 2ê°??´ìƒ?´ë©´ ?•ìƒ.
```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd tree
```

### rook-ceph-tools ?íƒœ ?•ì¸
```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph df
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd tree
```

---

## BeeGFS

### beegfs-mgmtd/meta Pod CrashLoopBackOff (Exit Code 127)
ë°”ì´?ˆë¦¬ ê²½ë¡œ ?¤ë¥˜. BeeGFS 7.4.6?€ `/opt/beegfs/sbin/`???¤ì¹˜??
```bash
kubectl -n beegfs-system logs deploy/beegfs-mgmtd
# master-1?ì„œ ë°”ì´?ˆë¦¬ ?„ì¹˜ ?•ì¸
find /opt/beegfs/sbin -name 'beegfs-mgmtd'
# ?¤ì¹˜ ?¬ë? ?•ì¸
ls /opt/beegfs/sbin/
```

### beegfs-mgmtd/meta/storage Pod CrashLoopBackOff (Exit Code 3)
`connDisableAuthentication` ë¯¸ì„¤?? ê¸°ì¡´ ?¨í‚¤ì§€ ê¸°ë³¸ê°’ì? `false`.
```bash
kubectl -n beegfs-system logs deploy/beegfs-mgmtd
# ?¤ë¥˜ ?ˆì‹œ: "No connAuthFile configured... set connDisableAuthentication to true"
# master-1?ì„œ conf ?•ì¸
grep connDisableAuthentication /etc/beegfs/beegfs-mgmtd.conf
# fix: ansible beegfs.yml ?¬ì‹¤??(force: yesë¡?conf ??–´?°ê¸°)
```

### beegfs-exporter OOMKilled
exporterê°€ ubuntu:24.04?ì„œ python3 apt-get ?¤ì¹˜ ??ë©”ëª¨ë¦?ì´ˆê³¼.
?„ì¬ êµ¬ì„±: `python:3.12-slim` ?´ë?ì§€ ?¬ìš© (apt-get ë¶ˆí•„??.
```bash
kubectl -n beegfs-system describe pod <exporter-pod>
# limits.memory: 128Mi ?•ì¸
```

### storaged DaemonSet Pod Pending (node selector ë¶ˆì¼ì¹?
Worker ?¸ë“œ??`role=worker` ?ˆì´ë¸??•ì¸:
```bash
kubectl get nodes --show-labels | grep worker
# ?ˆì´ë¸”ì´ ?†ìœ¼ë©?kubectl label node worker-1 role=worker
```

### BeeGFS ?¤í† ë¦¬ì? ?”ìŠ¤??ë§ˆìš´???¤íŒ¨
```bash
ssh -i ~/.ssh/storage-lab.pem ubuntu@<worker-ip>
lsblk                     # nvme3n1 ?•ì¸
sudo blkid /dev/nvme3n1   # ?Œì¼?œìŠ¤???•ì¸
mount | grep beegfs       # ë§ˆìš´???¬ë? ?•ì¸
```

### BeeGFS ?¬ì„¤ì¹?```bash
bash scripts/lifecycle/destroy_beegfs.sh && bash scripts/lifecycle/start_beegfs.sh
```

---

## PVC / CSI

### PVC Pending ?íƒœ ì§€??```bash
kubectl describe pvc <pvc-name>
kubectl logs -n rook-ceph deploy/rook-ceph-operator | tail -50
```

### StorageClass ?†ìŒ
```bash
kubectl get storageclass
# ceph-rbd, ceph-cephfs ?†ìœ¼ë©?bash scripts/lifecycle/start_ceph.sh

# beegfs-scratch ?†ìœ¼ë©?bash scripts/lifecycle/start_beegfs.sh
```
