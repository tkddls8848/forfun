# K8s Storage Lab

AWS 위에 Kubernetes + Ceph(rook-ceph) + BeeGFS 스토리지 통합 실습 환경을 자동 구성하는 프로젝트입니다.

## 아키텍처 개요

```
Internet
    │
    ▼
┌──────────────────────────────────────────┐
│  Bastion  t3.small  10.0.0.0/24 (public) │
│  - Ansible 제어 노드                      │
│  - HAProxy :6443 → 3× Master API         │
│  - HAProxy stats :9000                   │
└──────────┬───────────────────────────────┘
           │ VPC private  10.0.1.0/24
    ┌──────┴──────┐
    ▼             ▼
master-1/2/3   worker-1/2/3 ...
t3.large×3     m5.large×N
etcd HA        K8s 워크로드
K8s API        Ceph OSD×2 (10GB×2)
BeeGFS         BeeGFS storaged (8GB)
mgmtd/meta
```

| 역할 | 수 | 인스턴스 | 서브넷 | 주요 구성 |
|------|----|----------|--------|-----------|
| Bastion | 1 | t3.small | 10.0.0.0/24 (public) | Ansible, HAProxy(6443/9000) |
| K8s Master (HA) | 3 | t3.large | 10.0.1.0/24 (private) | etcd, kubeadm, BeeGFS mgmtd/meta |
| K8s Worker (HCI) | N | m5.large | 10.0.1.0/24 (private) | K8s 워크로드 + Ceph OSD×2 + BeeGFS storaged |

**EBS 구성 (워커당):** Ceph OSD-a 10GB + Ceph OSD-b 10GB + BeeGFS 8GB

## 접근 구조

```
[운영자]
  │
  ├─ ssh :22      → Bastion (public IP)
  │                    └─ ssh → Master / Worker (private IP)
  │
  └─ kubectl :6443 → Bastion HAProxy → master-1/2/3:6443
                      (health check, 장애 master 자동 제외)
```

## 스토리지 구성

| StorageClass | 백엔드 | Access Mode | 용도 |
|-------------|--------|-------------|------|
| `ceph-rbd` | Ceph RBD (rook-ceph) | RWO | 블록 스토리지 (DB, 단일 Pod) |
| `ceph-cephfs` | CephFS (rook-ceph) | RWX | 파일 공유 (다중 Pod 동시 접근) |
| `beegfs-scratch` | BeeGFS 7.4 CSI | RWX | 고성능 병렬 파일시스템 |

## 디렉토리 구조

```
k8s-storage-lab/
├── opentofu/                     # IaC (OpenTofu)
│   ├── main.tf
│   ├── variables.tf              # master_count(기본 3), worker_count
│   ├── outputs.tf
│   └── modules/
│       ├── vpc/                  # VPC, 서브넷(bastion/k8s), IGW, NAT GW
│       ├── security_group/       # Bastion SG / K8s HCI SG
│       ├── ec2/                  # EC2 인스턴스 + user_data
│       └── ebs/                  # EBS (Ceph OSD×2 + BeeGFS 8GB, 워커당)
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── aws_ec2.yml           # AWS EC2 동적 인벤토리
│   │   └── group_vars/
│   │       ├── all.yml           # 공통 변수
│   │       └── worker.yml
│   ├── playbooks/
│   │   ├── k8s.yml               # K8s HA 클러스터 구성 (HAProxy 포함)
│   │   └── beegfs.yml            # BeeGFS 설치 + K8s 매니페스트 적용
│   └── roles/
│       ├── common/               # OS 공통 (swap, sysctl, containerd, 커널 모듈)
│       ├── worker/               # Worker 추가 패키지
│       ├── cluster_setup/        # /etc/hosts, SSH key 배포
│       ├── kubernetes_common/    # kubelet, kubeadm, kubectl 설치
│       ├── kubernetes_master/    # kubeadm init (master-1), --upload-certs
│       ├── kubernetes_master_join/ # master-2/3 control-plane join
│       ├── kubernetes_worker/    # worker K8s join + label
│       ├── cni/                  # Flannel VXLAN
│       ├── addons/               # Metrics Server, Dashboard, Prometheus, Grafana, MetalLB
│       ├── haproxy/              # HAProxy 설치 (Bastion, k8s.yml에서 자동 실행)
│       └── beegfs_prep/          # BeeGFS 패키지 설치 + 디스크 포맷/마운트
├── manifests/
│   ├── beegfs/                   # BeeGFS 데몬 K8s 매니페스트
│   │   ├── 00-namespace.yaml
│   │   ├── 01-mgmtd.yaml         # mgmtd Deployment (master-1)
│   │   ├── 02-meta.yaml          # meta Deployment (master-1)
│   │   ├── 03-storage.yaml       # storaged DaemonSet (workers)
│   │   └── 04-storageclass.yaml  # beegfs-scratch StorageClass
│   ├── test-pvc/                 # StorageClass별 PVC 테스트 YAML
│   └── metallb-nginx/            # MetalLB + nginx LoadBalancer 예시
├── scripts/
│   └── install/
│       └── 01_ceph_install.sh    # rook-ceph operator + StorageClass
├── start_k8s.sh                  # 인프라 + K8s HA 클러스터 구성
├── start_ceph.sh                 # rook-ceph 구성
├── start_beegfs.sh               # BeeGFS 구성
├── destroy_ceph.sh               # rook-ceph 삭제 + OSD 초기화
├── destroy.sh                    # 전체 AWS 리소스 삭제
├── worker_add.sh                 # HCI Worker 노드 1대 추가 (스케일 아웃)
├── worker_remove.sh              # HCI Worker 노드 1대 제거 (스케일 인)
├── pause.sh                      # EC2 중지 (비용 절감)
└── resume.sh                     # EC2 재시작
```

## 사전 요구사항

| 항목 | 조건 |
|------|------|
| AWS CLI | v2, 자격증명 설정 완료 |
| OpenTofu | v1.6+ |
| jq | 설치 필요 |
| SSH Key Pair | AWS에 등록, `~/.ssh/storage-lab.pem` 배치 |

> **Windows 사용자:** 모든 스크립트는 Linux Bash 환경 전제. **WSL2에서 실행**하세요.
> ```bash
> cd /mnt/c/forfun/forfun/devops/k8s-storage-lab
> cp /mnt/c/path/to/storage-lab.pem ~/.ssh/ && chmod 400 ~/.ssh/storage-lab.pem
> ```

## 빠른 시작

```bash
# 1. tfvars 확인 (master_count 기본값 3)
vi opentofu/terraform.tfvars
# key_name     = "storage-lab"
# worker_count = 3

# 2. 인프라 + K8s HA 클러스터 구성
bash start_k8s.sh
# → OpenTofu: VPC/EC2/EBS 생성
# → Ansible: HAProxy(Bastion) + master-1 init + master-2/3 join + worker join + addons

# 3. rook-ceph 구성
bash start_ceph.sh

# 4. BeeGFS 구성
bash start_beegfs.sh

# 5. PVC 테스트
kubectl apply -f manifests/test-pvc/

# Worker 스케일 아웃 (1대 추가)
bash worker_add.sh

# Worker 스케일 인 (마지막 1대 제거)
bash worker_remove.sh

# rook-ceph 재설치
bash destroy_ceph.sh && bash start_ceph.sh

# 전체 삭제
bash destroy.sh
```

## HAProxy 리버스 프록시

Bastion의 HAProxy가 K8s API 서버(6443)를 3개 Master로 load balance합니다.

- **frontend k8s_api `:6443`** → **backend k8s_masters** (roundrobin, health check)
- Master 장애 시 자동 제외, 복구 시 자동 재포함
- **stats 페이지:** `http://BASTION_IP:9000/stats` (admin/admin)

설정은 `ansible/roles/haproxy/templates/haproxy.cfg.j2`에서 동적으로 생성됩니다.

## Worker 스케일 아웃/인

```bash
# Worker 추가 (K8s + Ceph OSD + BeeGFS 자동 구성)
bash worker_add.sh

# Worker 제거 (drain → Ceph OSD 안전 제거 → K8s delete → tofu)
bash worker_remove.sh
```

Ceph는 `useAllDevices: true`로 새 노드의 OSD 디스크를 자동 감지합니다.

## 주요 설계 결정

| 항목 | 선택 | 이유 |
|------|------|------|
| OS | Ubuntu 24.04 (Noble) | BeeGFS 7.4 공식 지원, nftables 네이티브 |
| K8s 버전 | 1.31 | stable, nftables 모드 지원 |
| Master HA | 3식 (etcd quorum) | 1대 장애 허용, HAProxy 자동 failover |
| Master 타입 | t3.large (8GB) | etcd 3노드 quorum 메모리 안정성 |
| Worker 타입 | m5.large (8GB) | Ceph OSD 지속 I/O → t3 버스트 크레딧 고갈 위험 |
| kube-proxy 모드 | nftables | Ubuntu 24.04 환경, Flannel iptables lock 경합 방지 |
| CNI | Flannel VXLAN | 경량 DaemonSet, AWS SG VXLAN 포트 허용 |
| Ceph 배포 | rook-ceph operator | HCI 환경 K8s 단일 제어면, CSI 자동 설치 |
| BeeGFS 배포 | K8s 컨테이너 (DaemonSet/Deployment) | HCI: chroot 방식으로 호스트 바이너리 실행 |
| BeeGFS 디스크 | 8GB gp2 EBS (`/dev/xvdd`) | Ceph OSD와 디바이스 분리, XFS 포맷 |
| HAProxy | Bastion Ansible 자동 구성 | master_count 변경 시 자동 반영 |
