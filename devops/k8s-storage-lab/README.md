# K8s Storage Lab

AWS 위에 Kubernetes + Ceph(rook-ceph) + IBM Spectrum Scale(GPFS) 스토리지 통합 실습 환경을 자동 구성하는 프로젝트입니다.

## 아키텍처 개요

| 역할 | 노드 수 | 인스턴스 | 서브넷 | 주요 구성 |
|------|---------|----------|--------|-----------|
| Bastion | 1 | t3.small | 10.0.0.0/24 | Ansible 제어 노드, HAProxy(6443) |
| K8s Master | 1 | t3.large | 10.0.1.0/24 | kubeadm, etcd, Flannel(VXLAN) |
| K8s Worker (HCI) | 3 | m5.large | 10.0.1.0/24 | k8s 워크로드 + Ceph OSD×2 |
| NSD (GPFS, K8s 편입) | 2 | t3.large | 10.0.2.0/24 | K8s worker + GPFS NSD 서버 (DaemonSet) |

**총 7대 EC2** / EBS: GPFS LUN 2개(10GB) + Ceph OSD 6개(worker당 2개, 10GB)

> **HCI(Hyper-Converged Infrastructure)**: worker 노드가 k8s 컴퓨트와 Ceph 스토리지 백엔드를 동시에 담당.
> **2안 NSD 편입**: NSD 노드를 K8s 클러스터 워커로 편입, taint(`role=gpfs-nsd:NoSchedule`)로 일반 Pod 차단,
> GPFS 데몬을 privileged DaemonSet으로 K8s가 관리.

## 접근 구조

```
[운영자]
  │
  ├─ ssh :22      → Bastion (public IP)
  │                    └─ ssh → Master / Worker / NSD (private IP)
  │
  └─ kubectl :6443 → Bastion HAProxy → Master:6443
```

## 디렉토리 구조

```
k8s-storage-lab/
├── opentofu/                     # IaC (OpenTofu)
│   ├── main.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   └── modules/
│       ├── vpc/                  # VPC, 서브넷(bastion/k8s/nsd), IGW, NAT GW
│       ├── security_group/       # Bastion SG / K8s HCI SG / NSD SG
│       ├── ec2/                  # EC2 인스턴스 + user_data
│       └── ebs/                  # EBS 볼륨 (Ceph OSD, GPFS LUN)
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── aws_ec2.yml           # AWS EC2 동적 인벤토리
│   │   └── group_vars/
│   │       ├── all.yml           # 공통 변수 (k8s_version, pod_cidr 등)
│   │       ├── worker.yml
│   │       └── nsd.yml
│   ├── playbooks/
│   │   ├── k8s.yml               # K8s 클러스터 구성 (NSD 편입 포함)
│   │   ├── gpfs.yml              # GPFS 설치 + DaemonSet 배포
│   │   └── haproxy.yml           # Bastion HAProxy 설치
│   └── roles/
│       ├── common/               # OS 공통 (swap, sysctl, containerd, 커널 모듈)
│       ├── worker/               # Worker 추가 패키지 (lvm2, chrony 등)
│       ├── nsd/                  # NSD GPFS 의존 패키지
│       ├── cluster_setup/        # /etc/hosts, SSH key 배포
│       ├── kubernetes_common/    # kubelet, kubeadm, kubectl 설치
│       ├── kubernetes_master/    # kubeadm init, kubeconfig, manifests 업로드
│       ├── kubernetes_worker/    # worker K8s join + label
│       ├── kubernetes_nsd/       # NSD K8s join + taint(role=gpfs-nsd:NoSchedule)
│       ├── cni/                  # Flannel VXLAN
│       ├── addons/               # Metrics Server, Dashboard, Prometheus, Grafana, MetalLB
│       ├── haproxy/              # HAProxy 설치 및 설정 (Bastion)
│       ├── gpfs_install/         # GPFS .deb 패키지 설치
│       ├── gpfs_cluster/         # GPFS 클러스터 생성, NSD 정의, FS 생성
│       └── gpfs_csi/             # IBM Spectrum Scale CSI 드라이버
├── manifests/
│   ├── test-pvc/                 # StorageClass별 PVC 테스트 YAML
│   ├── metallb-nginx/            # MetalLB + nginx LoadBalancer 예시
│   └── gpfs/
│       └── gpfs-daemonset.yaml   # GPFS NSD DaemonSet (privileged)
├── scripts/
│   └── install/
│       ├── 01_ceph_install.sh    # rook-ceph operator + StorageClass
│       ├── 02_nsd_setup.sh       # GPFS 클러스터 생성, NSD 정의, 마운트
│       └── 03_csi_gpfs.sh        # IBM Spectrum Scale CSI Helm 설치
├── gpfs-packages/                # IBM Spectrum Scale .deb 파일 배치 위치
├── start_k8s.sh                  # 인프라 + K8s 클러스터 구성 (NSD 편입 포함)
├── start_ceph.sh                 # rook-ceph 구성
├── destroy_ceph.sh               # rook-ceph 삭제 + OSD 초기화
├── destroy_gpfs.sh               # GPFS CSI + 클러스터 해체
├── destroy.sh                    # 전체 AWS 리소스 삭제
├── pause.sh                      # EC2 중지 (OSD 스냅샷 후 중지)
└── resume.sh                     # EC2 재시작 + Ansible 재전송
```

## Windows 사용자 안내

모든 스크립트는 **Linux Bash 환경**을 전제로 작성되어 있습니다.
**Windows에서는 WSL2를 통해 실행**해야 합니다.

```bash
cd /mnt/c/forfun/forfun/devops/k8s-storage-lab

mkdir -p ~/.ssh
cp /mnt/c/path/to/storage-lab.pem ~/.ssh/storage-lab.pem
chmod 400 ~/.ssh/storage-lab.pem
```

---

## 사전 요구사항

| 항목 | 조건 |
|------|------|
| AWS CLI | v2, 자격증명 설정 완료 |
| OpenTofu | v1.6+ |
| jq | 설치 필요 |
| SSH Key Pair | AWS에 등록, `~/.ssh/storage-lab.pem` 배치 |
| GPFS 패키지 | IBM Developer Edition .deb (GPFS 설치 시 필요) |

---

## 빠른 시작

```bash
# 1. terraform.tfvars 확인
vi opentofu/terraform.tfvars
# key_name     = "storage-lab"
# worker_count = 3

# 2. 인프라 + K8s 구성 (Bastion HAProxy + NSD K8s 편입 포함)
bash start_k8s.sh

# 3. rook-ceph 구성
bash start_ceph.sh

# 4. Bastion HAProxy 설치 (선택, K8s 구성 후)
# Bastion에서:
ansible-playbook -i ansible/inventory/ ansible/playbooks/haproxy.yml

# 5. GPFS 설치 (IBM 패키지 준비 후)
ansible-playbook -i ansible/inventory/ ansible/playbooks/gpfs.yml

# 6. PVC 테스트
kubectl apply -f manifests/test-pvc/

# rook-ceph만 재설치
bash destroy_ceph.sh && bash start_ceph.sh

# 전체 삭제
bash destroy.sh
```

---

## StorageClass 요약

| StorageClass | 백엔드 | Access Mode | 용도 |
|-------------|--------|-------------|------|
| `ceph-rbd` | Ceph RBD (rook-ceph) | RWO | 블록 스토리지 (DB, 단일 Pod) |
| `ceph-cephfs` | CephFS (rook-ceph) | RWX | 파일 공유 (다중 Pod 동시 접근) |
| `gpfs-scale` | IBM Spectrum Scale CSI | RWX | 고성능 병렬 파일시스템 |

---

## 주요 설계 결정

| 항목 | 선택 | 이유 |
|------|------|------|
| OS | Ubuntu 24.04 (Noble) | IBM Spectrum Scale CSI 호환, nftables 네이티브 |
| K8s 버전 | 1.31 | IBM Spectrum Scale CSI 지원, nftables 모드 stable |
| kube-proxy 모드 | nftables | Ubuntu 24.04 환경, Flannel과 iptables lock 경합 방지 |
| CNI | Flannel VXLAN (UDP 8472) | 경량 DaemonSet, AWS SG VXLAN 포트 허용으로 충분 |
| Ceph 배포 | rook-ceph operator | HCI 환경에서 K8s 단일 제어면, CSI 자동 설치 |
| NSD 아키텍처 | **K8s 편입 (2안)** | NSD 노드를 K8s 워커로 편입, GPFS 데몬을 DaemonSet으로 K8s 관리 |
| NSD taint | `role=gpfs-nsd:NoSchedule` | 일반 Pod 스케줄링 차단, GPFS DaemonSet만 실행 |
| HAProxy | Bastion에 설치 | K8s API(6443) 단일 진입점, master 증설 시 backend 자동 반영 |
| master 인스턴스 | t3.large (2vCPU, 8GB) | control plane 실사용 ~2.5GB, m5.large 대비 비용 절감 |
| worker 인스턴스 | m5.large (2vCPU, 8GB) | Ceph OSD + Prometheus 경합, t3 버스트 크레딧 고갈 위험 |
| nsd 인스턴스 | t3.large (2vCPU, 8GB) | GPFS GUI(Java) + kubelet 메모리 경합, t3.medium OOM 위험 |

---

## 트러블슈팅

### API server 다운 / kube-proxy CrashLoopBackOff

Ubuntu 24.04 nftables 환경에서 kube-proxy iptables 모드 시 Flannel과 `/run/xtables.lock` 경합 발생.
현재 구성은 `KubeProxyConfiguration mode: nftables` 기본 적용으로 재발하지 않습니다.

수동 적용:
```bash
kubectl -n kube-system get configmap kube-proxy -o yaml \
  | sed 's/mode: ""/mode: "nftables"/' \
  | kubectl apply -f -
kubectl -n kube-system rollout restart daemonset kube-proxy
```

### worker join 실패 (worker_join_command not found)

`--start-at-task`로 중간부터 재실행 시 token fact가 없는 경우:
```bash
ansible-playbook -i inventory/aws_ec2.yml playbooks/k8s.yml \
  --start-at-task "join 명령어 생성"
```

### rook-ceph 재설치

```bash
bash destroy_ceph.sh && bash start_ceph.sh
```

### Flannel Pod Pending / 노드 NotReady

```bash
kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
kubectl apply  -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```
