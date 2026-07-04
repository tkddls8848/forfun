# 02. ???¤í¬ë¦½íŠ¸ êµ¬ì¡°

## ì§„ì…???¤í¬ë¦½íŠ¸ (?„ë¡œ?íŠ¸ ë£¨íŠ¸)

| ?Œì¼ | ??•  |
|------|------|
| `start_k8s.sh` | ?¸í”„???ì„± + K8s HA ?´ëŸ¬?¤í„° êµ¬ì„± (HAProxy ?¬í•¨) |
| `start_ceph.sh` | rook-ceph ?¤ì¹˜ |
| `start_beegfs.sh` | BeeGFS ?¤ì¹˜ (?¨í‚¤ì§€ + K8s ?°ëª¬ ë°°í¬) |
| `worker_add.sh` | HCI Worker ?¸ë“œ 1?€ ì¶”ê? (?¤ì????„ì›ƒ) |
| `worker_remove.sh` | HCI Worker ?¸ë“œ 1?€ ?œê±° (?¤ì????? |
| `destroy_beegfs.sh` | BeeGFS ?? œ (beegfs-system ?¤ì„?¤í˜?´ìŠ¤ + ?¨í‚¤ì§€) |
| `destroy_ceph.sh` | rook-cephë§??? œ + OSD ?”ìŠ¤??ì´ˆê¸°??|
| `destroy_k8s.sh` | ?„ì²´ AWS ë¦¬ì†Œ???? œ (tofu destroy) |
| `pause.sh` | EC2 ì¤‘ì? (ë¹„ìš© ?ˆê°, OSD ?¤ëƒ…???¬í•¨) |
| `resume.sh` | EC2 ?¬ì‹œ??+ Ansible/Manifest ?¬ì „??|

---

## start_k8s.sh ?ë¦„

```
[0/5] ?¬ì „ ?”êµ¬?¬í•­ ?•ì¸ (tofu, aws, ssh, scp, SSH ??
[1/5] tofu apply (?¸í”„???ì„±)
       ??BASTION_IP, BASTION_PRIVATE_IP ?˜ì§‘
[2/5] Bastion SSH ?€ê¸?[3/5] SSH ??+ Ansible Playbook ?„ì†¡
[4/5] ?˜ë¨¸ì§€ ?¸ë“œ ë¶€???€ê¸?(masterÃ—3 + workerÃ—N)
[5/5] Ansible k8s.yml ?¤í–‰
       --extra-vars "control_plane_endpoint=BASTION_PRIVATE_IP"
```

`control_plane_endpoint`??Bastion??**private IP**:6443 (HAProxy).
K8s ?¸ë“œ?¤ì´ VPC ?´ë??ì„œ HAProxyë¡??‘ê·¼?©ë‹ˆ??

---

## ansible/roles/hci_node

Worker ?„ìš© ì¶”ê? ?¤ì • (Ceph OSD + BeeGFS storaged ?´ë‹¹ ?¸ë“œ).
`k8s.yml` ?Œë ˆ??3ë²ˆì—??`hosts: worker` ?€?ìœ¼ë¡??¤í–‰.

| ??ª© | ?´ìš© |
|------|------|
| ?¨í‚¤ì§€ | `lvm2`, `chrony`, `linux-modules-extra-aws` |
| Ceph ëª¨ë“ˆ | `rbd`, `ceph` ??`/etc/modules-load.d/k8s.conf` ?±ë¡ + `modprobe` |
| chrony | systemd ?œì„±??|

---

## scripts/system/ceph_install.sh

1. **Helm ?¤ì¹˜** (master-1)
2. **rook-ceph Helm repo** + namespace ?ì„±
3. **rook-ceph Operator ë°°í¬** ??60ì´?CRD watch ?ˆì •???€ê¸?4. **?Œì»¤ rbd ëª¨ë“ˆ ë¡œë“œ ?•ì¸**
5. **CephCluster CR ë°°í¬**
   - `useAllDevices: true` (BeeGFS ?”ìŠ¤??`/dev/nvme3n1`?€ XFS ?¬ë§· ?„ë£Œ ?íƒœ???ë™ ?œì™¸)
   - `osd_pool_default_size: "2"`, `osd_pool_default_min_size: "1"`
   - placement: control-plane ?œì™¸ (OSD??worker ?„ìš©)
6. **Ceph HEALTH_OK ?€ê¸?*
7. **CSI Provisioner ??master ?¸ë“œ ë°°ì¹˜**
   - `rook-ceph-operator-config` ConfigMap ?¨ì¹˜
     - `CSI_PROVISIONER_NODE_AFFINITY`: `node-role.kubernetes.io/control-plane=`
     - `CSI_PROVISIONER_TOLERATIONS`: control-plane NoSchedule ?Œì¸???ˆìš©
   - csi-cephfsplugin-provisioner, csi-rbdplugin-provisioner rollout restart
   - worker CPU ?¬ìœ  ?•ë³´ (HCI ?˜ê²½ ??master CPUê°€ ?¬ìœ  ?ˆìŒ)
8. **rook-ceph-tools toolbox ë°°í¬**
9. **CephBlockPool + StorageClass (ceph-rbd, RWO)**
10. **CephFilesystem + StorageClass (ceph-cephfs, RWX)**

---

## worker_add.sh ?ë¦„

```
[0/4] ?¬ì „ ?”êµ¬?¬í•­ ?•ì¸
[1/4] tofu apply -var="worker_count=N+1"  (EC2 + EBS ì¶”ê?)
[2/4] ??Worker ë¶€???€ê¸?[3/4] Ansible: common/worker/cluster_setup/k8s_common/worker ?¤í–‰
[4/4] Ansible: beegfs.yml ?¤í–‰ (BeeGFS storaged ì¶”ê?)
```

Ceph OSD??rook-ceph operatorê°€ ???¸ë“œ??ë¹??”ìŠ¤?¬ë? ?ë™ ê°ì??©ë‹ˆ??

---

## worker_remove.sh ?ë¦„

```
[0/5] ?¬ì „ ?”êµ¬?¬í•­ ?•ì¸ (ìµœì†Œ 1?€ ? ì? ê²€ì¦?
[1/5] BeeGFS storaged ?íƒœ ?•ì¸
[2/5] kubectl drain (eviction + daemonset ë¬´ì‹œ)
[3/5] Ceph OSD ?ˆì „ ?œê±° (out ??down ??purge, rebalancing 60ì´??€ê¸?
[4/5] kubectl delete node
[5/5] tofu apply -var="worker_count=N-1"  (EC2 + EBS ?œê±°)
```

---

## destroy_ceph.sh ?ë¦„

```
[1/3] ?¸í”„???•ë³´ ?˜ì§‘ (bastion IP, worker IPs)
[2/3] .env ?ì„± + kubectl ?¤ì¹˜
[3/3] rook-ceph ?? œ (bastion ?ê²© ?¤í–‰)
  [1/5] API ?œë²„ ?°ê²° ?•ì¸ ??ë¯¸ì‘????[2~4] ?¤í‚µ
  [2/5] StorageClass ?? œ
  [3/5] CephFilesystem / BlockPool ?? œ
  [4/5] CephCluster ?? œ (finalizer ?œê±°) + Helm uninstall + CRD ?? œ
  [5/5] Worker OSD ?”ìŠ¤??ì´ˆê¸°??(nvme1n1, nvme2n1ë§???nvme3n1?€ BeeGFS ? ì?)
```

---

## destroy_k8s.sh

```bash
source scripts/.env          # IP ë¯¸ë¦¬ ?˜ì§‘
tofu destroy -auto-approve
rm -f scripts/.env ~/.kube/config-k8s-storage-lab
ssh-keygen -R <ê°??¸ë“œ IP>   # known_hosts ?•ë¦¬
```

---

## destroy_beegfs.sh

```
[1/3] ?¸í”„???•ë³´ ?˜ì§‘ (bastion IP)
[2/3] .env ë¡œë“œ + kubectl ?¤ì •
[3/3] K8s ë¦¬ì†Œ???? œ (bastion ?ê²© ?¤í–‰)
  [1/3] beegfs-system ?¤ì„?¤í˜?´ìŠ¤ ?? œ (StorageClass ?¬í•¨)
  [2/3] BeeGFS CSI ?œë¼?´ë²„ ?? œ
  [3/3] Worker ?¸ìŠ¤???¨í‚¤ì§€ ?œê±° (beegfs-storage, beegfs-client ??
```
