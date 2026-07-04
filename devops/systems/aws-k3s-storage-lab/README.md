# k3s-storage-lab

k3s(?„ë¡ ?? + cephadm/BeeGFS 8(ë°±ì—”?? ë¶„ë¦¬ êµ¬ì„± ê¸°ëŠ¥ê²€ì¦??˜ê²½.
EC2 2?€, ~$20/??(ì£?5??Ã— 5?œê°„ ê¸°ì?).

## ?„í‚¤?ì²˜

```
EC2 #1 t3.large ??Frontend          EC2 #2 t3.medium ??Backend
?Œâ??€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€??         ?Œâ??€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€????k3s server (master)    ??         ??cephadm (Squid)        ????k3s agent-1 (worker-1) ?‚â??€?€?€?€?€?€?€?€?¶â”‚  MON/OSD/MGR/MDS       ????k3s agent-2 (worker-2) ??         ??                       ????                       ??         ??BeeGFS 8.3             ????Ceph CSI (RBD+CephFS)  ??         ?? mgmtd/meta/storaged   ????BeeGFS CSI v1.8.0+     ??         ??                       ???”â??€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€??         ?”â??€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€??```

## ?¬ì „ ?”êµ¬?¬í•­

- AWS CLI ?¤ì • ?„ë£Œ (`aws configure`)
- OpenTofu ?¤ì¹˜
- Packer ?¤ì¹˜ (AMI ë¹Œë“œ ??
- EC2 Key Pair (`storage-lab`) ë°?PEM ?Œì¼ (`~/.ssh/storage-lab.pem`)

## ë¹ ë¥¸ ?œì‘

```bash
# 1. tfvars ?˜ì • (key_name ?•ì¸)
vi opentofu/terraform.tfvars

# 2. ?„ì²´ ?ë™ êµ¬ì„± (??15~20ë¶?
bash start.sh

# 3. ê²€ì¦?ssh -i ~/.ssh/storage-lab.pem ec2-user@<FRONTEND_IP>
bash scripts/system/05_verify.sh
```

## Packer AMI ë¹Œë“œ (? íƒ)

?¬ì „ ë¹Œë“œ??AMIë¥??¬ìš©?˜ë©´ ?¨í‚¤ì§€ ?¤ì¹˜ ë°?BeeGFS ì»¤ë„ ëª¨ë“ˆ ë¹Œë“œ ?œê°„???¨ì¶•?????ˆìŠµ?ˆë‹¤.

```bash
# ?¬ì „ ì¡°ê±´ ?ê? + ë¹Œë“œ ?µí•© ?¤í–‰
bash scripts/provision/00_build_ami.sh [REGION] [KEY_NAME] [PEM_FILE]
# ê¸°ë³¸ê°? ap-northeast-2 / storage-lab / ~/.ssh/storage-lab.pem
```

ì§ì ‘ Packerë¡?ë¹Œë“œ??ê²½ìš°:

```bash
cd packer/k3s-storage-lab

# frontend AMIë§?ë¹Œë“œ
packer build -only="amazon-ebs.frontend" -var-file=variables.pkrvars.hcl .

# backend AMIë§?ë¹Œë“œ
packer build -only="amazon-ebs.backend" -var-file=variables.pkrvars.hcl .

# ?????™ì‹œ ë¹Œë“œ
packer build -var-file=variables.pkrvars.hcl .
```

ë¹Œë“œ ?„ë£Œ ??`opentofu/terraform.tfvars`??AMI ID ë°˜ì˜:

```hcl
ami_frontend = "ami-0xxxxxxxxxxxxxxxxx"
ami_backend  = "ami-0yyyyyyyyyyyyyyyyy"
```

**Frontend AMI ?¬ì „ ?¬í•¨ ??ª©:**

| ??ª© | ?´ìš© |
|------|------|
| k3s ë°”ì´?ˆë¦¬ | v1.32.3+k3s1 (?œë¹„???±ë¡ ?œì™¸) |
| BeeGFS ?´ë¼?´ì–¸???¨í‚¤ì§€ | beegfs-client, beegfs-utils, beegfs-tools |
| beegfs.ko | ì»¤ë„ ëª¨ë“ˆ ?¬ì „ ë¹Œë“œ + ?¤ì¹˜ (RDMA ë¹„í™œ?? |
| helm | ë°”ì´?ˆë¦¬ ?¤ì¹˜ + ceph-csi repo ìºì‹œ |
| git + BeeGFS CSI driver | v1.8.0 ?¬ì „ ?´ë¡  (`/opt/beegfs-csi-driver`) |

## ?¨ê³„ë³??¤í–‰

```bash
# Stage 1: ?¸í”„??+ k3s + manifests ?„ì†¡
bash scripts/lifecycle/start_1_infra_k3s.sh

# Stage 2: Ceph ë°±ì—”??+ Ceph CSI (ceph-rbd, ceph-cephfs StorageClass)
bash scripts/lifecycle/start_2_ceph.sh

# Stage 3: BeeGFS ë°±ì—”??+ BeeGFS CSI (beegfs-scratch StorageClass)
bash scripts/lifecycle/start_3_beegfs.sh

# ê²€ì¦?ssh -i ~/.ssh/storage-lab.pem ec2-user@<FRONTEND_IP> 'bash ~/05_verify.sh'
```

ë¡¤ë°±:

```bash
bash scripts/lifecycle/rollback_3_beegfs.sh   # BeeGFS CSI + ë°±ì—”???œê±°
bash scripts/lifecycle/rollback_2_ceph.sh     # Ceph CSI + ?´ëŸ¬?¤í„° ?œê±°
bash scripts/lifecycle/rollback_1_infra.sh    # AWS ?¸í”„???? œ
```

## ?? œ

```bash
bash destroy.sh
```

## ë²„ì „

| ??ª© | ë²„ì „ |
|------|------|
| OS | RHEL 9.7 (ami-0a67d323f227ce006) |
| Kernel | 5.14.0-xxx (RHEL 9 ê¸°ë³¸, ê³ ì • ë¶ˆí•„?? |
| k3s | v1.32.3+k3s1 |
| Ceph | Squid v19.2.x (cephadm) |
| BeeGFS | 8.3 (Community Edition) |
| BeeGFS CSI | v1.8.0+ |
| Ceph CSI | v3.12.x (Helm) |

## ì£¼ìš” ?¤ê³„ ê²°ì •

| ??ª© | ? íƒ | ?´ìœ  |
|------|------|------|
| OS | RHEL 9 | BeeGFS 8.x ê³µì‹ RPM ì§€?? SELinux ê¸°ë³¸ ?‘ì¬ |
| BeeGFS | 8.3 Community Edition | RHEL 9 ?„ìš© (Ubuntu deb ?¨í‚¤ì§€ ë¯¸ì œê³?, mgmtd TOML ?•ì‹ |
| k3s SELinux | --selinux ?Œë˜ê·?+ k3s-selinux RPM | RHEL 9 SELinux enforcing ?˜ê²½ ?„ìˆ˜ |
| BeeGFS mgmtd | TOML ?•ì‹ (`tls-disable=true`, `auth-disable=true`) | BeeGFS 8 mgmtd??TOML, TLS ê¸°ë³¸ ?”êµ¬ |
| BeeGFS meta/storage | .conf ?•ì‹ (`connDisableAuthentication=true`) | 8ë²„ì „?ì„œ??.conf ? ì? |
| DKMS ì»¤ë„ ë¹Œë“œ | `kernel-devel-$(uname -r)` ëª…ì‹œ | ìµœì‹  kernel-develê³??¤í–‰ ì»¤ë„ ë²„ì „ ë¶ˆì¼ì¹?ë°©ì? |
| sudo PATH | `export PATH="/usr/local/bin:..."` ?¤í¬ë¦½íŠ¸ ìµœìƒ??| RHEL 9 sudo secure_path??/usr/local/bin ë¯¸í¬??|
| BeeGFS helperd | ?œê±° | BeeGFS 8?ì„œ ?ì? |
| Ceph ?¸ì¦ | cephadm bootstrap `--allow-fqdn-hostname` | AWS EC2 hostname??FQDN ?•ì‹ |
