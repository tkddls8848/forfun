# K8s Storage Lab

AWS 위에 Kubernetes + Ceph(rook-ceph) + IBM Spectrum Scale(GPFS) 스토리지 통합 실습 환경을 자동 구성하는 프로젝트입니다.

## 아키텍처 개요

| 역할 | 노드 수 | 인스턴스 | 서브넷 | 주요 구성 |
|------|---------|----------|--------|-----------|
| K8s Master | 1 | m5.large | 10.0.1.0/24 | kubeadm, etcd, Flannel(VXLAN) |
| K8s Worker (HCI) | 3 | m5.large | 10.0.1.0/24 | k8s 워크로드 + Ceph OSD×2 |
| NSD (GPFS) | 2 | t3.medium | 10.0.2.0/24 | Spectrum Scale NSD 서버 |

**총 6대 EC2** / EBS: GPFS LUN 2개 + Ceph OSD 6개(worker당 2개, 10GB)

> **HCI(Hyper-Converged Infrastructure)**: worker 노드가 k8s 컴퓨트와 Ceph 스토리지 백엔드를 동시에 담당.
> Ceph는 rook-ceph operator로 k8s Pod 형태로 배포되어 단일 제어면으로 관리됩니다.

## 디렉토리 구조

```
k8s-storage-lab/
├── opentofu/                     # IaC (OpenTofu)
│   ├── main.tf                   # 루트 모듈 — provider, data, module 호출
│   ├── variables.tf              # 전역 변수 (region, project_name, vpc_cidr, key_name, worker_count)
│   ├── terraform.tfvars          # key_name, worker_count 실제 값 설정
│   └── modules/
│       ├── vpc/                  # VPC, 서브넷 2개(k8s/nsd), IGW, 라우트 테이블
│       ├── security_group/       # HCI SG(k8s+Ceph 포트 통합) / NSD SG
│       ├── ec2/                  # EC2 + user_data 스크립트
│       │   └── user_data/
│       │       ├── common.sh     # master용 (swap off, containerd, sysctl, 커널 모듈)
│       │       ├── worker.sh     # worker용 (common + lvm2, chrony, linux-modules-extra-aws)
│       │       └── nsd.sh        # GPFS NSD 전용
│       └── ebs/                  # EBS 볼륨 + attachment (worker_count 동적 반영)
├── scripts/
│   ├── .env                      # 00번 실행 후 자동 생성 (IP 배열, SSH_KEY)
│   ├── 00_hosts_setup.sh         # IP 수집, /etc/hosts 배포, 클러스터 내부 SSH 키 생성
│   ├── 01_k8s_install.sh         # kubeadm init/join, Flannel VXLAN, nftables 모드 검증
│   ├── 02_ceph_install.sh        # rook-ceph operator + CephCluster(순차 OSD) + StorageClass
│   ├── 03_csi_ceph.sh            # rook-ceph StorageClass 확인
│   ├── 04_gpfs_install.sh        # GPFS .deb 패키지 설치 (IBM 수동 필요)
│   ├── 05_nsd_setup.sh           # GPFS 클러스터 생성, NSD 정의, 마운트
│   ├── 06_csi_gpfs.sh            # IBM Spectrum Scale CSI Helm 설치
│   └── 99_test_pvc.sh            # 3개 StorageClass PVC 바인딩 테스트
├── start_k8s.sh                  # 인프라 + K8s 클러스터 구성
├── start_ceph.sh                 # rook-ceph 구성
├── destroy_ceph.sh               # rook-ceph만 삭제 + OSD 디스크 초기화
└── destroy.sh                    # 전체 AWS 리소스 삭제 (tofu destroy)
```

## Windows 사용자 안내

모든 스크립트는 **Linux Bash 환경**을 전제로 작성되어 있습니다.
**Windows에서는 WSL2를 통해 실행**해야 합니다.

```bash
# WSL2 셸에서 프로젝트 디렉토리로 이동
cd /mnt/c/forfun/forfun/devops/k8s-storage-lab

# PEM 키 준비 (/mnt/c/ 경로는 chmod가 적용되지 않으므로 WSL 홈으로 복사)
mkdir -p ~/.ssh
cp /mnt/c/forfun/forfun/devops/k8s-storage-lab/storage-lab.pem ~/.ssh/storage-lab.pem
chmod 400 ~/.ssh/storage-lab.pem
```

---

## 사전 요구사항

| 항목 | 조건 |
|------|------|
| AWS CLI | v2, 자격증명 설정 완료 |
| OpenTofu | v1.6+ |
| jq | 설치 필요 |
| kubectl | 설치 필요 |
| helm | v3+ |
| SSH Key Pair | AWS에 등록, `~/.ssh/storage-lab.pem` 배치 |
| GPFS 패키지 | IBM Developer Edition .deb (GPFS 설치 시 필요) |

---

## 빠른 시작

```bash
# 1. terraform.tfvars 확인
vi opentofu/terraform.tfvars
# key_name     = "storage-lab"
# worker_count = 3

# 2. 인프라 + K8s 구성
bash start_k8s.sh

# 3. rook-ceph 구성
bash start_ceph.sh

# 4. GPFS 수동 설치 (IBM 패키지 준비 후)
bash scripts/04_gpfs_install.sh
bash scripts/05_nsd_setup.sh
bash scripts/06_csi_gpfs.sh

# 5. 전체 테스트
bash scripts/99_test_pvc.sh

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
| OS | Ubuntu 24.04 (Noble) | IBM Spectrum Scale CSI 호환 확인, nftables 네이티브 |
| K8s 버전 | 1.31 | IBM Spectrum Scale CSI 지원, nftables 모드 stable |
| **kube-proxy 모드** | **nftables** | Ubuntu 24.04는 nftables 네이티브 환경. iptables 모드(기본값)는 Flannel과 `/run/xtables.lock` 경합 발생 → kube-proxy CrashLoopBackOff → 클러스터 네트워킹 붕괴. K8s 1.31 nftables 모드를 기본값으로 적용 (`KubeProxyConfiguration mode: nftables`) |
| **커널 모듈** | modules-load.d | 패키지 설치 완료 후 reboot → 새 커널 기준으로 overlay, br_netfilter, nf_tables, nft_masq, rbd, ceph 자동 로드 |
| CNI | Flannel VXLAN (UDP 8472) | 경량 DaemonSet, AWS SG에서 VXLAN 포트 허용으로 충분 |
| Ceph 배포 | rook-ceph operator | HCI 환경에서 k8s 단일 제어면, CSI 자동 설치 |
| Ceph mon | count=3 | quorum 구성, 과반수 생존 시 클러스터 정상 운영 |
| Ceph OSD 초기화 | 워커별 순차 추가 | 일제 초기화 시 I/O 스파이크 → API server 과부하 방지 |
| Ceph replication | size=2 | 3노드 랩 환경 기준, osd_pool_default_size도 2로 통일 |
| worker_count | terraform.tfvars 동적 설정 | 노드 수 변경 시 EC2/EBS/스크립트 자동 반영 |
| master 인스턴스 | m5.large (2 vCPU, 8GB) | 3노드 랩 control plane 실사용 1.2GB, 8GB로 충분 |
| worker 인스턴스 | m5.large (2 vCPU, 8GB) | Ceph OSD 지속 I/O → t3 burstable CPU 크레딧 고갈 위험, m5 고정 성능 |
| nsd 인스턴스 | t3.medium (2 vCPU, 4GB) | GPFS NSD 서버, I/O 부하 낮음 |

---

## 트러블슈팅

### API server 다운 / kube-proxy CrashLoopBackOff

**원인**: Ubuntu 24.04 nftables 환경에서 kube-proxy가 iptables 모드로 기동 시
Flannel과 `/run/xtables.lock` 경합 → kube-proxy 크래시 → 클러스터 네트워킹 단절 → API server 응답 불가.

**현재 구성**: `01_k8s_install.sh`에서 kubeadm init 시 `KubeProxyConfiguration mode: nftables`를 기본 적용하므로 재발하지 않습니다.

기동 중인 클러스터에 수동 적용이 필요한 경우:

```bash
kubectl -n kube-system get configmap kube-proxy -o yaml \
  | sed 's/mode: ""/mode: "nftables"/' \
  | kubectl apply -f -
kubectl -n kube-system rollout restart daemonset kube-proxy
```

### kubelet 재시작으로 API server 복구

```bash
ssh -i ~/.ssh/storage-lab.pem ubuntu@<master-ip> \
  "sudo systemctl restart kubelet"
```

### K8s 클러스터 재설치

```bash
# master에서
sudo kubeadm reset -f
sudo rm -rf /etc/cni /etc/kubernetes /var/lib/kubelet /var/lib/etcd ~/.kube
sudo systemctl restart containerd

# 로컬에서 재설치
bash scripts/01_k8s_install.sh
```

### rook-ceph 재설치

```bash
bash destroy_ceph.sh
bash start_ceph.sh
```

### Flannel Pod Pending / 노드 NotReady

```bash
kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
kubectl apply  -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```
