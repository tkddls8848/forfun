# K8s Storage Lab

AWS ?„ì— Kubernetes + Ceph(rook-ceph) + BeeGFS ?¤í† ë¦¬ì? ?µí•© ?¤ìŠµ ?˜ê²½???ë™ êµ¬ì„±?˜ëŠ” ?„ë¡œ?íŠ¸?…ë‹ˆ??

## ?„í‚¤?ì²˜ ê°œìš”

```
Internet
    ??    ???Œâ??€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€???? Bastion  t3.small  10.0.0.0/24 (public) ???? - Ansible ?œì–´ ?¸ë“œ                      ???? - HAProxy :6443 ??3Ã— Master API         ???? - HAProxy stats :9000                   ???”â??€?€?€?€?€?€?€?€?€?¬â??€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€??           ??VPC private  10.0.1.0/24
    ?Œâ??€?€?€?€?€?´â??€?€?€?€?€??    ??            ??master-1/2/3   worker-1/2/3 ...
t3.largeÃ—3     m5.largeÃ—N
etcd HA        K8s ?Œí¬ë¡œë“œ
K8s API        Ceph OSDÃ—1 (5GB)
BeeGFS         BeeGFS storaged (8GB)
mgmtd/meta
Ceph CSI Provisioner
```

| ??•  | ??| ?¸ìŠ¤?´ìŠ¤ | ?œë¸Œ??| ì£¼ìš” êµ¬ì„± |
|------|----|----------|--------|-----------|
| Bastion | 1 | t3.small | 10.0.0.0/24 (public) | Ansible, HAProxy(6443/9000) |
| K8s Master (HA) | 3 | t3.large | 10.0.1.0/24 (private) | etcd, kubeadm, BeeGFS mgmtd/meta, Ceph CSI Provisioner |
| K8s Worker (HCI) | N | m5.large | 10.0.1.0/24 (private) | K8s ?Œí¬ë¡œë“œ + Ceph OSDÃ—1 + BeeGFS storaged (ì»¤ë„ 6.8 ê³ ì •) |

**EBS êµ¬ì„± (?Œì»¤??:** Ceph OSD 5GB + BeeGFS 8GB

## ?‘ê·¼ êµ¬ì¡°

```
[?´ì˜??
  ??  ?œâ? ssh :22      ??Bastion (public IP)
  ??                   ?”â? ssh ??Master / Worker (private IP)
  ??  ?”â? kubectl :6443 ??Bastion HAProxy ??master-1/2/3:6443
                      (health check, ?¥ì•  master ?ë™ ?œì™¸)
```

## ?¤í† ë¦¬ì? êµ¬ì„±

| StorageClass | ë°±ì—”??| Access Mode | ?©ë„ |
|-------------|--------|-------------|------|
| `ceph-rbd` | Ceph RBD (rook-ceph) | RWO | ë¸”ë¡ ?¤í† ë¦¬ì? (DB, ?¨ì¼ Pod) |
| `ceph-cephfs` | CephFS (rook-ceph) | RWX | ?Œì¼ ê³µìœ  (?¤ì¤‘ Pod ?™ì‹œ ?‘ê·¼) |
| `beegfs-scratch` | BeeGFS 7.4.6 CSI | RWX | ê³ ì„±??ë³‘ë ¬ ?Œì¼?œìŠ¤??|

> **BeeGFS 8 ?…ê·¸?ˆì´??ë¶ˆê?**: BeeGFS 8.x??RHEL/CentOS RPMë§??œê³µ. Ubuntu deb ?¨í‚¤ì§€ ë¯¸ì œê³?404 ?•ì¸).
> Ubuntu ê¸°ë°˜ ???©ì? BeeGFS 7.4.6??ìµœì‹  ?¬ìš© ê°€??ë²„ì „?…ë‹ˆ??

## ?”ë ‰? ë¦¬ êµ¬ì¡°

```
k8s-storage-lab/
?œâ??€ opentofu/                     # IaC (OpenTofu)
??  ?œâ??€ main.tf
??  ?œâ??€ variables.tf              # master_count(ê¸°ë³¸ 3), worker_count
??  ?œâ??€ outputs.tf
??  ?”â??€ modules/
??      ?œâ??€ vpc/                  # VPC, ?œë¸Œ??bastion/k8s), IGW, NAT GW
??      ?œâ??€ security_group/       # Bastion SG / K8s HCI SG
??      ?œâ??€ ec2/                  # EC2 ?¸ìŠ¤?´ìŠ¤ + user_data
??      ?”â??€ ebs/                  # EBS (Ceph OSDÃ—1 5GB + BeeGFS 8GB, ?Œì»¤??
?œâ??€ packer/                       # Packer AMI ë¹Œë“œ (? íƒ)
??  ?œâ??€ worker.pkr.hcl            # Worker: containerd + kubeadm + BeeGFS 7.4.6 + ì»¤ë„ 6.8
??  ?œâ??€ master.pkr.hcl            # Master: containerd + kubeadm
??  ?œâ??€ bastion.pkr.hcl           # Bastion: ansible-core + boto3
??  ?œâ??€ common.pkr.hcl            # ê³µí†µ ë³€??+ plugin ? ì–¸
??  ?œâ??€ variables.pkrvars.hcl     # AMI ID, Key Pair ????  ?”â??€ scripts/
??      ?œâ??€ base.sh               # ê³µí†µ ?¨í‚¤ì§€ + ì»¤ë„ ëª¨ë“ˆ + sysctl
??      ?œâ??€ worker_kernel.sh      # ì»¤ë„ 6.8 ?¤ì¹˜ + 5?¨ê³„ ê³ ì • + GRUB ?¤ì •
??      ?œâ??€ worker.sh             # containerd + kubeadm + BeeGFS ëª¨ë“ˆ ë¹Œë“œ + lvm2/chrony/linux-modules-extra-aws + Ceph ëª¨ë“ˆ ?±ë¡
??      ?œâ??€ master.sh             # containerd + kubeadm
??      ?”â??€ bastion.sh            # ansible-core + boto3 + collections
?œâ??€ ansible/
??  ?œâ??€ ansible.cfg
??  ?œâ??€ inventory/
??  ??  ?œâ??€ aws_ec2.yml           # AWS EC2 ?™ì  ?¸ë²¤? ë¦¬
??  ??  ?”â??€ group_vars/
??  ??      ?œâ??€ all.yml           # ê³µí†µ ë³€????  ??      ?”â??€ worker.yml
??  ?œâ??€ playbooks/
??  ??  ?œâ??€ k8s.yml               # K8s HA ?´ëŸ¬?¤í„° êµ¬ì„± (HAProxy ?¬í•¨)
??  ??  ?”â??€ beegfs.yml            # BeeGFS ?¤ì¹˜ + K8s ë§¤ë‹ˆ?˜ìŠ¤???ìš©
??  ?”â??€ roles/
??      ?œâ??€ node_base/            # OS ê³µí†µ (swap, sysctl, containerd, ì»¤ë„ ëª¨ë“ˆ)
??      ?œâ??€ hci_node/             # Worker ì¶”ê? ?¨í‚¤ì§€ (lvm2, chrony, linux-modules-extra-aws) + Ceph ëª¨ë“ˆ ë¡œë“œ ??Packer AMI ?¬ìš© ??ami_base ?œê·¸ë¡??¤í‚µ
??      ?œâ??€ cluster_setup/        # /etc/hosts, SSH key ë°°í¬
??      ?œâ??€ k8s_common/           # kubelet, kubeadm, kubectl ?¤ì¹˜
??      ?œâ??€ control_plane/        # kubeadm init (master-1), --upload-certs
??      ?œâ??€ control_plane_join/   # master-2/3 control-plane join
??      ?œâ??€ worker/               # worker K8s join + label
??      ?œâ??€ cni/                  # Flannel VXLAN
??      ?œâ??€ addons/               # Metrics Server, Dashboard, Prometheus, Grafana, MetalLB
??      ?œâ??€ haproxy/              # HAProxy ?¤ì¹˜ (Bastion, k8s.yml?ì„œ ?ë™ ?¤í–‰)
??      ?”â??€ beegfs_prep/          # BeeGFS ?¨í‚¤ì§€ ?¤ì¹˜ + ì»¤ë„ ê³ ì • + ?”ìŠ¤???¬ë§·/ë§ˆìš´???œâ??€ manifests/
??  ?œâ??€ beegfs/                   # BeeGFS ?°ëª¬ K8s ë§¤ë‹ˆ?˜ìŠ¤????  ??  ?œâ??€ 00-namespace.yaml
??  ??  ?œâ??€ 01-mgmtd.yaml         # mgmtd Deployment (master-1)
??  ??  ?œâ??€ 02-meta.yaml          # meta Deployment (master-1)
??  ??  ?œâ??€ 03-storage.yaml       # storaged DaemonSet (workers)
??  ??  ?œâ??€ 04-storageclass.yaml  # beegfs-scratch StorageClass
??  ??  ?œâ??€ 05-monitoring.yaml    # beegfs-exporter (python:3.12-slim, Prometheus)
??  ??  ?”â??€ 06-grafana-dashboard.yaml  # Grafana ?€?œë³´???ë™ import
??  ?œâ??€ examples/                 # StorageClassë³?PVC ?ŒìŠ¤??YAML
??  ?”â??€ networking/               # MetalLB + nginx LoadBalancer ?ˆì‹œ
?œâ??€ scripts/
??  ?œâ??€ ceph_install.sh           # rook-ceph operator + StorageClass
??  ?œâ??€ check_resources.sh        # ?¸ë“œ ?ì› ?„í™© ?˜ì§‘
??  ?”â??€ fix_beegfs_storage_conf.sh # BeeGFS ?¤í† ë¦¬ì? ?¤ì • ?˜ì •
?œâ??€ start_k8s.sh                  # ?¸í”„??+ K8s HA ?´ëŸ¬?¤í„° êµ¬ì„±
?œâ??€ start_ceph.sh                 # rook-ceph êµ¬ì„±
?œâ??€ start_beegfs.sh               # BeeGFS êµ¬ì„±
?œâ??€ destroy_beegfs.sh             # BeeGFS ?? œ (beegfs-system ?¤ì„?¤í˜?´ìŠ¤)
?œâ??€ destroy_ceph.sh               # rook-ceph ?? œ + OSD ì´ˆê¸°???œâ??€ destroy_k8s.sh                # ?„ì²´ AWS ë¦¬ì†Œ???? œ (tofu destroy)
?œâ??€ worker_add.sh                 # HCI Worker ?¸ë“œ 1?€ ì¶”ê? (?¤ì????„ì›ƒ)
?œâ??€ worker_remove.sh              # HCI Worker ?¸ë“œ 1?€ ?œê±° (?¤ì?????
?œâ??€ pause.sh                      # EC2 ì¤‘ì? (ë¹„ìš© ?ˆê°)
?”â??€ resume.sh                     # EC2 ?¬ì‹œ??```

## ?¬ì „ ?”êµ¬?¬í•­

| ??ª© | ì¡°ê±´ |
|------|------|
| AWS CLI | v2, ?ê²©ì¦ëª… ?¤ì • ?„ë£Œ |
| OpenTofu | v1.6+ |
| jq | ?¤ì¹˜ ?„ìš” |
| SSH Key Pair | AWS???±ë¡, `~/.ssh/storage-lab.pem` ë°°ì¹˜ |

> **Windows ?¬ìš©??** ëª¨ë“  ?¤í¬ë¦½íŠ¸??Linux Bash ?˜ê²½ ?„ì œ. **WSL2?ì„œ ?¤í–‰**?˜ì„¸??
> ```bash
> cd /mnt/c/forfun/forfun/devops/systems/aws-kubeadm-storage-lab
> cp /mnt/c/path/to/storage-lab.pem ~/.ssh/ && chmod 400 ~/.ssh/storage-lab.pem
> ```

## ë¹ ë¥¸ ?œì‘

```bash
# 1. tfvars ?•ì¸ (master_count ê¸°ë³¸ê°?3)
vi opentofu/terraform.tfvars
# key_name     = "storage-lab"
# worker_count = 3

# 2. ?¸í”„??+ K8s HA ?´ëŸ¬?¤í„° êµ¬ì„±
bash scripts/lifecycle/start_k8s.sh
# ??OpenTofu: VPC/EC2/EBS ?ì„±
# ??Ansible: HAProxy(Bastion) + master-1 init + master-2/3 join + worker join + addons

# 3. rook-ceph êµ¬ì„±
bash scripts/lifecycle/start_ceph.sh

# 4. BeeGFS êµ¬ì„±
bash scripts/lifecycle/start_beegfs.sh

# 5. PVC ?ŒìŠ¤??kubectl apply -f manifests/examples/

# Worker ?¤ì????„ì›ƒ (1?€ ì¶”ê?)
bash scripts/lifecycle/worker_add.sh

# Worker ?¤ì?????(ë§ˆì?ë§?1?€ ?œê±°)
bash scripts/lifecycle/worker_remove.sh

# rook-ceph ?¬ì„¤ì¹?bash scripts/lifecycle/destroy_ceph.sh && bash scripts/lifecycle/start_ceph.sh

# BeeGFS ?¬ì„¤ì¹?bash scripts/lifecycle/destroy_beegfs.sh && bash scripts/lifecycle/start_beegfs.sh

# ?„ì²´ ?? œ
bash scripts/lifecycle/destroy_k8s.sh
```

## Packer AMI ë¹Œë“œ (? íƒ)

?¬ì „ ë¹Œë“œ??AMIë¥??¬ìš©?˜ë©´ Worker ì»¤ë„ ?¤ìš´ê·¸ë ˆ?´ë“œ + BeeGFS ëª¨ë“ˆ ë¹Œë“œ ?œê°„???¨ì¶•?????ˆìŠµ?ˆë‹¤.

```bash
cd packer

# Worker AMIë§?ë¹Œë“œ (ì»¤ë„ 6.8 ê³ ì • + BeeGFS 7.4.6 ëª¨ë“ˆ ?¬ì „ ë¹Œë“œ)
packer build -only="amazon-ebs.worker" -var-file=variables.pkrvars.hcl .

# ?„ì²´ ë¹Œë“œ
packer build -var-file=variables.pkrvars.hcl .
```

ë¹Œë“œ ?„ë£Œ ??`opentofu/terraform.tfvars`??AMI ID ë°˜ì˜:

```hcl
ami_worker  = "ami-0xxxxxxxxxxxxxxxxx"
ami_master  = "ami-0yyyyyyyyyyyyyyyyy"
ami_bastion = "ami-0zzzzzzzzzzzzzzzzz"
```

Packer AMI ?¬ìš© ???¨í‚¤ì§€ ?¤ì¹˜ ?¨ê³„ë¥?ê±´ë„ˆ?ë‹ˆ??

```bash
USE_PACKER_AMI=true bash scripts/lifecycle/start_k8s.sh
```

**Worker AMI ?¬ì „ ?¬í•¨ ??ª©:**

| ??ª© | ?´ìš© |
|------|------|
| ì»¤ë„ | 6.8.0-aws ê³ ì • (5?¨ê³„ ë³´í˜¸) |
| containerd | 1.7.22-1 |
| K8s ë°”ì´?ˆë¦¬ | kubeadm, kubelet, kubectl 1.31 |
| BeeGFS ?¨í‚¤ì§€ | beegfs-storage, beegfs-client, beegfs-helperd, beegfs-utils 7.4.6 |
| BeeGFS ì»¤ë„ ëª¨ë“ˆ | beegfs.ko ?¬ì „ ë¹Œë“œ + ?ë™ ë¡œë“œ ?±ë¡ |
| HCI ?¨í‚¤ì§€ | lvm2, chrony, linux-modules-extra-aws, linux-headers-aws |
| Ceph ì»¤ë„ ëª¨ë“ˆ | rbd, ceph ??`/etc/modules-load.d/k8s.conf` ?±ë¡ |

> Ansible `hci_node` ë¡¤ì˜ ?¨í‚¤ì§€ ?¤ì¹˜/chrony ?œì„±??modules-load.d ?±ë¡ ?œìŠ¤?¬ëŠ”
> `ami_base` ?œê·¸ë¡?ë¬¶ì—¬ ?ˆì–´ `USE_PACKER_AMI=true` ???ë™ ?¤í‚µ?©ë‹ˆ??

## HAProxy ë¦¬ë²„???„ë¡??
Bastion??HAProxyê°€ K8s API ?œë²„(6443)ë¥?3ê°?Masterë¡?load balance?©ë‹ˆ??

- **frontend k8s_api `:6443`** ??**backend k8s_masters** (roundrobin, health check)
- Master ?¥ì•  ???ë™ ?œì™¸, ë³µêµ¬ ???ë™ ?¬í¬??- **stats ?˜ì´ì§€:** `http://BASTION_IP:9000/stats` (admin/admin)

?¤ì •?€ `ansible/roles/haproxy/templates/haproxy.cfg.j2`?ì„œ ?™ì ?¼ë¡œ ?ì„±?©ë‹ˆ??

## Worker ?¤ì????„ì›ƒ/??
```bash
# Worker ì¶”ê? (K8s + Ceph OSD + BeeGFS ?ë™ êµ¬ì„±)
bash scripts/lifecycle/worker_add.sh

# Worker ?œê±° (drain ??Ceph OSD ?ˆì „ ?œê±° ??K8s delete ??tofu)
bash scripts/lifecycle/worker_remove.sh
```

Ceph??`deviceFilter: ^nvme1n1$`ë¡?OSD ?”ìŠ¤?¬ë? ê°ì??©ë‹ˆ??(nvme2n1 BeeGFS ?œì™¸).

## ì£¼ìš” ?¤ê³„ ê²°ì •

| ??ª© | ? íƒ | ?´ìœ  |
|------|------|------|
| OS | Ubuntu 24.04 (Noble) | BeeGFS 7.4.6 ê³µì‹ deb ì§€??(BeeGFS 8?€ Ubuntu ?¨í‚¤ì§€ ë¯¸ì œê³? |
| K8s ë²„ì „ | 1.31 | stable, nftables ëª¨ë“œ ì§€??|
| Master HA | 3??(etcd quorum) | 1?€ ?¥ì•  ?ˆìš©, HAProxy ?ë™ failover |
| Master ?€??| t3.large (8GB) | etcd 3?¸ë“œ quorum + BeeGFS mgmtd/meta + Ceph CSI Provisioner ???¤ì¸¡ ë©”ëª¨ë¦?96%+ (4GB ë¶€ì¡? |
| Worker ?€??| m5.large (8GB) | Ceph OSD ì§€??I/O ??t3 ë²„ìŠ¤???¬ë ˆ??ê³ ê°ˆ ?„í—˜ |
| kube-proxy ëª¨ë“œ | nftables | Ubuntu 24.04 ?˜ê²½, Flannel iptables lock ê²½í•© ë°©ì? |
| Worker ì»¤ë„ | 6.8.0-aws ê³ ì • (5?¨ê³„) | BeeGFS 7.4.6 ìµœë? ì§€??ì»¤ë„ 6.11 ??6.12+ ê°ì? ???ë™ ?¤ìš´ê·¸ë ˆ?´ë“œ ??K8s ?¤ì¹˜ ì§„í–‰ |
| ì»¤ë„ ê³ ì • ë©”ì»¤?ˆì¦˜ | APT preferences + apt-mark hold + êµ¬ì»¤???œê±° + GRUB savedefault ë¹„í™œ?±í™” + unattended-upgrades ì°¨ë‹¨ | 5?¨ê³„ ì¡°í•©?¼ë¡œ ?ë™ ?…ê·¸?ˆì´???„ì „ ì°¨ë‹¨ |
| containerd | 1.7.22-1 ê³ ì • + hold | K8s 1.31 ?¸í™˜ ê²€ì¦? ?ë™ ?…ê·¸?ˆì´??ë°©ì? |
| CNI | Flannel v0.26.1 VXLAN | ë²„ì „ ê³ ì •, K8s 1.28+ ì§€???•ì¸ |
| Ceph ë°°í¬ | rook-ceph operator | HCI ?˜ê²½ K8s ?¨ì¼ ?œì–´ë©? CSI ?ë™ ?¤ì¹˜ |
| Ceph ?”ë°”?´ìŠ¤ | `deviceFilter: ^nvme[12]n1$` | BeeGFS ?„ìš© nvme3n1 ê²½í•© ë°©ì? (?¤í–‰ ?œì„œ ë¬´ê?) |
| BeeGFS ì»¤ë„ ëª¨ë“ˆ | ?ì²´ ë¹Œë“œ ?œìŠ¤??| BeeGFS 7.x??DKMS ë¯¸ì‚¬????`/opt/beegfs/src/client/client_module_7/build/` |
| BeeGFS ë°°í¬ | K8s ì»¨í…Œ?´ë„ˆ (DaemonSet/Deployment) | chroot ë°©ì‹?¼ë¡œ ?¸ìŠ¤??ë°”ì´?ˆë¦¬ ?¤í–‰ (`/opt/beegfs/sbin/`) |
| Ceph CSI Provisioner | master ?¸ë“œ ë°°ì¹˜ | worker CPU ?¬ìœ  ?•ë³´ (HCI ?˜ê²½) |
| BeeGFS ?”ìŠ¤??| 8GB gp2 EBS (`/dev/xvdd` ??nvme2n1) | Ceph OSD?€ ?”ë°”?´ìŠ¤ ë¶„ë¦¬, XFS ?¬ë§· |
| HAProxy | Bastion Ansible ?ë™ êµ¬ì„± | master_count ë³€ê²????ë™ ë°˜ì˜ |

## ë²„ì „

| ??ª© | ë²„ì „ |
|------|------|
| OS | Ubuntu 24.04 LTS (Noble) |
| Kernel (Worker) | 6.8.0-aws (ê³ ì •) |
| Kubernetes | 1.31 |
| Containerd | 1.7.22-1 |
| BeeGFS | 7.4.6 |
| Ceph | Squid (rook-ceph, ìµœì‹ ) |
| Flannel CNI | v0.26.1 |
