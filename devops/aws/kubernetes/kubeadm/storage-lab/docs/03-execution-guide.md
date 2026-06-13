# 03. ?¨ê³„ë³??¤í–‰ ê°€?´ë“œ

## ?¬ì „ ?”êµ¬?¬í•­

| ??ª© | ì¡°ê±´ |
|------|------|
| AWS CLI | v2, ?ê²©ì¦ëª… ?¤ì • ?„ë£Œ |
| OpenTofu | v1.6+ |
| jq | ?¤ì¹˜ ?„ìš” |
| SSH Key Pair | AWS???±ë¡, `~/.ssh/storage-lab.pem` ë°°ì¹˜ |

> Windows ?¬ìš©?? **WSL2**?ì„œ ?¤í–‰. PEM ?¤ë? WSL ?ˆìœ¼ë¡?ë³µì‚¬ ??`chmod 400`.

---

## ?¤í–‰ ?ë¦„ ?”ì•½

```
terraform.tfvars ?˜ì • (key_name, worker_count)
       ??bash scripts/lifecycle/start_k8s.sh          ???¸í”„??+ K8s HA 3??+ HAProxy (??25~30ë¶?
       ??bash scripts/lifecycle/start_ceph.sh         ??rook-ceph (??15~20ë¶?
       ??bash scripts/lifecycle/start_beegfs.sh       ??BeeGFS 7.4.6 (??10~15ë¶?
       ??kubectl apply -f manifests/examples/
```

---

## Step 0: ?¬ì „ ì¤€ë¹?
```bash
ls ~/.ssh/storage-lab.pem
chmod 400 ~/.ssh/storage-lab.pem

vi opentofu/terraform.tfvars
# key_name     = "storage-lab"
# worker_count = 3
# master_count = 3   # ê¸°ë³¸ê°? ?ëµ ê°€??```

---

## Step 1: ?¸í”„??+ K8s HA êµ¬ì„±

```bash
bash scripts/lifecycle/start_k8s.sh
```

?´ë? ?¤í–‰ ?œì„œ:
1. `[0/5]` ?¬ì „ ?”êµ¬?¬í•­ ?•ì¸
2. `[1/5]` `tofu apply` ??Bastion + MasterÃ—3 + WorkerÃ—N + EBS ?ì„±
   - BASTION_PRIVATE_IP ?˜ì§‘ (HAProxy endpoint)
3. `[2/5]` Bastion SSH ?€ê¸?4. `[3/5]` SSH ??+ ansible/ + manifests/ ?„ì†¡
5. `[4/5]` ëª¨ë“  ?¸ë“œ ë¶€???€ê¸?(ProxyJump ?•ì¸)
6. `[5/5]` `ansible-playbook k8s.yml --extra-vars "control_plane_endpoint=BASTION_PRIVATE_IP"`:
   - **[Play 0.5] Worker ì»¤ë„ 6.8 ê³ ì •** ??6.12+ ê°ì? ??6.8 ?¤ì¹˜ ??GRUB ë³€ê²???reboot
   - **[Play 0.6] ì»¤ë„ ê²€ì¦?ê²Œì´??* ??6.8 ?„ë‹ˆë©??„ì²´ ì¤‘ë‹¨
   - **HAProxy ?¤ì •** (Bastion, masterÃ—3 backend ?ë™ ?ì„±)
   - node_base ??hci_node ??cluster_setup ??k8s_common
   - **master-1 kubeadm init** (`--control-plane-endpoint BASTION_PRIVATE_IP:6443 --upload-certs`)
   - CNI (Flannel VXLAN)
   - **master-2/3 control-plane join** (serial: 1)
   - worker join
   - addons (Metrics Server, Dashboard, Prometheus, Grafana, MetalLB)
   - Bastion /etc/hosts + SSH config ?±ë¡

?„ë£Œ ???•ì¸ (Bastion?ì„œ):
```bash
export KUBECONFIG=~/.kube/config-k8s-storage-lab
kubectl get nodes -o wide
# master-1/2/3, worker-1~N  ëª¨ë‘ Ready

# HAProxy stats
curl http://localhost:9000/stats | grep -i backend
```

---

## Step 2: rook-ceph êµ¬ì„±

```bash
bash scripts/lifecycle/start_ceph.sh
```

1. Helm ?¤ì¹˜ (master-1)
2. rook-ceph operator ë°°í¬ + ?ˆì •???€ê¸?60s)
3. rbd ì»¤ë„ ëª¨ë“ˆ ?•ì¸
4. CephCluster CR ë°°í¬ (`deviceFilter: ^nvme[12]n1$` ??nvme3n1 BeeGFS ?„ìš© ëª…ì‹œ???œì™¸)
5. OSD ?ˆì •???€ê¸?(5???°ì† ?™ì¼ ??
6. HEALTH_OK ?€ê¸?7. CSI Provisioner ??master ?¸ë“œ ?¬ë°°ì¹?(worker CPU ?¬ìœ  ?•ë³´)
8. StorageClass ?ì„± (ceph-rbd, ceph-cephfs)

?„ë£Œ ???•ì¸:
```bash
kubectl -n rook-ceph get pods -o wide
kubectl get storageclass
# ceph-rbd, ceph-cephfs ?•ì¸
```

---

## Step 3: BeeGFS êµ¬ì„±

```bash
bash scripts/lifecycle/start_beegfs.sh
```

1. ansible/manifests ?¬ì „??2. `ansible-playbook beegfs.yml`:
   - BeeGFS 7.4.6 APT ?€?¥ì†Œ + ?¨í‚¤ì§€ ?¤ì¹˜ (noble ê³µì‹ ì§€??
   - Worker: ì»¤ë„ ëª¨ë“ˆ ë¹Œë“œ (`/opt/beegfs/src/client/client_module_7/build/`) + modprobe
   - Master: `/mnt/beegfs/mgmtd`, `/mnt/beegfs/meta` ?”ë ‰? ë¦¬ ?ì„±
   - Worker: `/dev/nvme3n1` XFS ?¬ë§· ??`/mnt/beegfs/storage` ë§ˆìš´??   - ?¤ì • ?Œì¼ ?ì„± (`sysMgmtdHost`, `connDisableAuthentication=true`)
   - K8s ë§¤ë‹ˆ?˜ìŠ¤???ìš© (namespace, mgmtd/meta Deployment, storaged DaemonSet, StorageClass)
   - CSI Driver: git clone + kustomize ë°°í¬ (`kubectl apply -k`)

?„ë£Œ ???•ì¸:
```bash
kubectl -n beegfs-system get pods -o wide
kubectl get storageclass
# beegfs-scratch ?•ì¸
```

---

## Step 4: PVC ?ŒìŠ¤??
```bash
kubectl apply -f manifests/examples/test-pvc-rbd.yaml
kubectl apply -f manifests/examples/test-pvc-cephfs.yaml
kubectl apply -f manifests/examples/test-pvc-beegfs.yaml
kubectl get pvc
```

---

## Worker ?¤ì????„ì›ƒ/??
```bash
# Worker 1?€ ì¶”ê? (K8s + Ceph + BeeGFS ?ë™ êµ¬ì„±)
bash scripts/lifecycle/worker_add.sh

# Worker 1?€ ?œê±° (?ˆì „ drain ??Ceph OSD purge ??delete ??tofu ì¶•ì†Œ)
bash scripts/lifecycle/worker_remove.sh
```

---

## ?¬ì„¤ì¹?
```bash
# rook-ceph ?¬ì„¤ì¹?bash scripts/lifecycle/destroy_ceph.sh && bash scripts/lifecycle/start_ceph.sh

# BeeGFS ?¬ì„¤ì¹?bash scripts/lifecycle/destroy_beegfs.sh && bash scripts/lifecycle/start_beegfs.sh

# ?„ì²´ ?? œ
bash scripts/lifecycle/destroy_k8s.sh
```

---

## EC2 ì¤‘ì?/?¬ì‹œ??(ë¹„ìš© ?ˆê°)

```bash
bash scripts/lifecycle/pause.sh    # OSD ?¤ëƒ…????EC2 ì¤‘ì?
bash scripts/lifecycle/resume.sh   # EC2 ?¬ì‹œ??+ ìµœì‹  playbook ?¬ì „??```

---

## ?ˆìƒ ë¹„ìš© (ap-northeast-2, ?¤í–‰ ì¤?ê¸°ì?)

| ë¦¬ì†Œ??| ?˜ëŸ‰ | ?œê°„??|
|--------|------|--------|
| t3.small (bastion Ã— 1) | 1 | ~$0.026 |
| t3.large (master Ã— 3) | 3 | ~$0.250 |
| m5.large (worker Ã— 3) | 3 | ~$0.288 |
| EBS gp2 20GB (ë£¨íŠ¸ Ã— 7) | 7 | ë¯¸ë? |
| EBS gp2 5GB (Ceph OSD Ã— 6) | 6 | ë¯¸ë? |
| EBS gp2 8GB (BeeGFS Ã— 3) | 3 | ë¯¸ë? |
| **?©ê³„** | | **~$0.56/h** |

> ë¯¸ì‚¬????`bash scripts/lifecycle/pause.sh` ?ëŠ” `bash destroy.sh`.
