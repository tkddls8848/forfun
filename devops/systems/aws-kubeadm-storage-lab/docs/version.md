# ë²„ì „ ?•ë³´

?¸í”„??êµ¬ì„±???ìš©??ëª¨ë“  êµ¬ì„±?”ì†Œ??ë²„ì „ ?•ë³´?…ë‹ˆ??

---

## 1. IaC ë°??´ë¼?°ë“œ ?¸í”„??
?„ì¹˜: `opentofu/main.tf`
- OpenTofu: >= 1.6.0
- AWS Provider: ~> 5.0 (hashicorp/aws)
- OS: Ubuntu 24.04 LTS (Noble Numbat)
  - AMI ?„í„°: ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*
  - Owner: 099720109477 (Canonical)

---

## 2. EC2 ?¸ìŠ¤?´ìŠ¤ ?€??
?„ì¹˜: `opentofu/modules/ec2/main.tf`

| ?¸ë“œ | ?€??| vCPU | RAM | ??•  |
|------|------|------|-----|------|
| Bastion | t3.small | 2 | 2GB | Ansible ?œì–´ ?¸ë“œ, HAProxy |
| Master | t3.large | 2 | 8GB | K8s HA control plane (etcd Ã—3) + BeeGFS mgmtd/meta + Ceph CSI Provisioner |
| Worker | m5.large | 2 | 8GB | HCI (K8s + Ceph OSD + BeeGFS storaged) |

---

## 3. ?¤í† ë¦¬ì? êµ¬ì„±

- EBS ë³¼ë¥¨ ?€?? gp2
- Root ë³¼ë¥¨: 20GB (ëª¨ë“  ?¸ìŠ¤?´ìŠ¤ ê³µí†µ)
- Ceph OSD: ?Œì»¤??1ê°? 5GB (`/dev/xvdb` ??nvme1n1)
- BeeGFS ?¤í† ë¦¬ì?: ?Œì»¤??1ê°? 8GB (`/dev/xvdd` ??nvme2n1, XFS ?¬ë§·)

---

## 4. Kubernetes ?¤íƒ

?„ì¹˜: `ansible/inventory/group_vars/all.yml`
- Kubernetes: 1.31
- kubeadm API: kubeadm.k8s.io/v1beta4
- kube-proxy:
  - ëª¨ë“œ: nftables
  - API: kubeproxy.config.k8s.io/v1alpha1
- CNI: Flannel v0.26.1 (ë²„ì „ ê³ ì •, K8s 1.28+ ì§€??
  - ëª¨ë“œ: VXLAN
  - ?¬íŠ¸: UDP 8472
  - POD CIDR: 10.244.0.0/16
- kubectl / kubelet / kubeadm: 1.31
- Worker ì»¤ë„: 6.8.0-aws ê³ ì • (BeeGFS 7.4.6 ìµœë? ì§€??ì»¤ë„ 6.11, k8s.yml Play 0.5?ì„œ ?ë™ ê³ ì •)

---

## 5. Ceph ?¤í† ë¦¬ì? ?¤íƒ

?„ì¹˜: `scripts/system/ceph_install.sh`
- Rook-Ceph Operator: v1.16.6
  - Helm repository: https://charts.rook.io/release
  - Chart: rook-release/rook-ceph
- Ceph: v19.2.3
  - Image: quay.io/ceph/ceph:v19.2.3
- Ceph API: ceph.rook.io/v1
- ë³µì œ ?¤ì •:
  - osd_pool_default_size: 2
  - osd_pool_default_min_size: 1
  - Block Pool / CephFS replicated size: 2
- MON: 3ê°?(quorum)
- MGR: 1ê°?(pg_autoscaler ?œì„±??
- Dashboard: ?œì„±??(SSL ë¹„í™œ?±í™”)
- MDS: activeCount=1, activeStandby=false
- OSD ë°°ì¹˜: worker ?¸ë“œë§?- ?”ë°”?´ìŠ¤ ? íƒ: `deviceFilter: ^nvme1n1$` (nvme2n1 BeeGFS ?„ìš© ?œì™¸)

---

## 6. BeeGFS ?¤í† ë¦¬ì? ?¤íƒ

?„ì¹˜: `ansible/roles/beegfs_prep/`, `manifests/beegfs/`
- BeeGFS: 7.4.6 (Ubuntu 24.04 Noble ê³µì‹ ì§€????7.4.6ë¶€??
  - APT ?€?¥ì†Œ: https://www.beegfs.io/release/beegfs_7.4.6/
  - ìµœë? ì§€??ì»¤ë„: 6.11 (worker ì»¤ë„ 6.8ë¡?ê³ ì • ?„ìˆ˜)
- êµ¬ì„±?”ì†Œ:
  - mgmtd: Deployment 1ê°?(master-1, port 8008)
  - meta: Deployment 1ê°?(master-1, port 8005)
  - storaged: DaemonSet (all workers, port 8003)
  - helperd: systemd (all workers, CSI ?˜ì¡´, port 8004, `connDisableAuthentication=true`)
- ?°ëª¬ ?¤í–‰ ë°©ì‹: K8s ì»¨í…Œ?´ë„ˆ (`ubuntu:24.04` + `chroot /host`)
- ì»¤ë„ ëª¨ë“ˆ ë¹Œë“œ: ?ì²´ ë¹Œë“œ ?œìŠ¤??(`/opt/beegfs/src/client/client_module_7/build/`, DKMS ë¯¸ì‚¬??
- ?¤í† ë¦¬ì? ?”ë ‰? ë¦¬: `/mnt/beegfs/storage` (XFS, 8GB EBS)
- CSI Driver: beegfs.csi.netapp.com v1.8.0 (ThinkParQ/NetApp)
  - StorageClass mountOptions: ?†ìŒ (rsize/wsize??BeeGFS ë¯¸ì???
- ëª¨ë‹ˆ?°ë§: Prometheus exporter (`manifests/beegfs/05-monitoring.yaml`)
  - beegfs-ctl ê¸°ë°˜ ì»¤ìŠ¤?€ exporter (port 9100)
  - ServiceMonitor ??kube-prometheus-stack ?ë™ scrape
  - Grafana ?€?œë³´???ë™ import (`06-grafana-dashboard.yaml`)

---

## 7. ?ë™??ë°?ê´€ë¦??„êµ¬

?„ì¹˜: `opentofu/modules/ec2/user_data/bastion.sh`
- Python: 3.12.x (Ubuntu 24.04 ê¸°ë³¸)
  - ?¨í‚¤ì§€: python3, python3-pip, pipx
- Ansible: ansible-core 2.20.x (pipx ìµœì‹  stable)
  - ?¤ì¹˜: pipx install ansible-core
  - Python ?”êµ¬?¬í•­: >= 3.12
  - ì¶”ê? ?˜ì¡´?? boto3, botocore (pipx inject)
- Ansible Collections:
  - amazon.aws
  - ansible.posix
  - community.general (>= 12.0.0)
  - community.crypto
- Ansible ?¤ì • (ansible.cfg):
  - stdout_callback: ansible.builtin.default
  - result_format: yaml
- HAProxy: ìµœì‹  (apt, Bastion???¤ì¹˜)
  - K8s API ?¬íŠ¸: 6443
  - Stats ?¬íŠ¸: 9000
- Helm: v3+ (ìµœì‹ )
  - ?¤ì¹˜: https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
- jq: ìµœì‹ 

---

## 8. Addons (K8s ?´ëŸ¬?¤í„°)

?„ì¹˜: `ansible/roles/addons/`
- Metrics Server: ìµœì‹  (Helm)
- Kubernetes Dashboard: ìµœì‹  (Helm)
- kube-prometheus-stack (Prometheus + Grafana + Alertmanager + node-exporter)
  - Prometheus retention: 7d
  - Prometheus memory limit: 1Gi
  - Grafana NodePort: 30300
  - Prometheus NodePort: 30090
  - Alertmanager NodePort: 30093
- MetalLB: v0.14.9
  - ëª¨ë“œ: L2
  - IP ?€?? 10.0.1.200-10.0.1.220

---

## 9. StorageClass

| StorageClass | Provisioner | Access Mode | ë¹„ê³  |
|---|---|---|---|
| ceph-rbd | rook-ceph.rbd.csi.ceph.com | RWO | imageFormat:2, layering |
| ceph-cephfs | rook-ceph.cephfs.csi.ceph.com | RWX | Filesystem: labfs |
| beegfs-scratch | beegfs.csi.netapp.com | RWX | volDirBasePath: /k8s/dynamic |

---

## 10. ?œìŠ¤???¨í‚¤ì§€ (Ubuntu 24.04)

- Container Runtime: containerd.io 1.7.22-1 (ë²„ì „ ê³ ì • + dpkg hold)
- ê³µí†µ ?¨í‚¤ì§€: curl, ca-certificates, gnupg, git, nfs-common, open-iscsi, conntrack, socat, nftables
- Worker ì¶”ê? ?¨í‚¤ì§€: lvm2, chrony, linux-modules-extra-aws, xfsprogs, nvme-cli
- BeeGFS ?˜ì¡´?? beegfs-client, beegfs-helperd, beegfs-utils, xfsprogs, dkms

---

## 11. ?¤íŠ¸?Œí¬ êµ¬ì„±

- VPC CIDR: 10.0.0.0/16
- Subnet:
  - Bastion: 10.0.0.0/24 (public)
  - K8s (master + worker): 10.0.1.0/24 (private)
- ë³´ì•ˆ ê·¸ë£¹:
  - Bastion SG: SSH(22), HAProxy(6443), Stats(9000)
  - K8s HCI SG: K8s + Ceph + Flannel + BeeGFS(8003-8008) + VPC ?´ë? ?„ì²´ ?ˆìš©

---

## 12. ì»¤ë„ ëª¨ë“ˆ

?ë™ ë¡œë“œ ?¤ì • (modules-load.d):
- ê³µí†µ: overlay, br_netfilter, nf_tables, nft_masq
- Worker ì¶”ê?: rbd, ceph

---

## ?¸í™˜??ì°¸ê³ 

| ì¡°í•© | ë²„ì „ |
|------|------|
| Kubernetes ??Rook | K8s 1.31 ??Rook v1.16.6 ??|
| Rook ??Ceph | Rook v1.16.6 ??Ceph v19.2.3 ??|
| Ubuntu ??BeeGFS | Ubuntu 24.04 ??BeeGFS 7.4 ??(ì»¤ë„ 6.8 ê³ ì • ?„ìˆ˜) |
| K8s ??kube-proxy | K8s 1.31 ??nftables ëª¨ë“œ stable ??|
