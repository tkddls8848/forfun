# K8s Storage Lab

AWS 위에 Kubernetes + Ceph(rook-ceph) + IBM Spectrum Scale(GPFS) 스토리지 통합 실습 환경을 자동 구성하는 프로젝트입니다.

## 아키텍처 개요

| 역할 | 노드 수 | 인스턴스 | 서브넷 | 주요 구성 |
|------|---------|----------|--------|-----------|
| K8s Master | 1 | m5.xlarge | 10.0.1.0/24 | kubeadm, etcd, Flannel(VXLAN) |
| K8s Worker (HCI) | 4 | m5.large | 10.0.1.0/24 | k8s 워크로드 + Ceph OSD×2 |
| NSD (GPFS) | 2 | t3.medium | 10.0.2.0/24 | Spectrum Scale NSD 서버 |

**총 7대 EC2** / EBS: GPFS LUN 2개 + Ceph OSD 8개(worker당 2개)

> **HCI(Hyper-Converged Infrastructure)**: worker 노드가 k8s 컴퓨트와 Ceph 스토리지 백엔드를 동시에 담당.
> Ceph는 rook-ceph operator로 k8s Pod 형태로 배포되어 단일 제어면으로 관리됩니다.

## 디렉토리 구조

```
k8s-storage-lab/
├── opentofu/                     # IaC (OpenTofu)
│   ├── main.tf                   # 루트 모듈 — provider, data, module 호출
│   ├── variables.tf              # 전역 변수 (region, project_name, vpc_cidr, key_name)
│   ├── outputs.tf                # 전체 IP 출력
│   ├── terraform.tfvars          # ← key_name 등 실제 값 설정
│   └── modules/
│       ├── vpc/                  # VPC, 서브넷 2개(k8s/nsd), IGW, 라우트 테이블
│       │   ├── main.tf
│       │   └── variables.tf
│       ├── security_group/       # HCI SG(k8s+Ceph 포트 통합) / NSD SG
│       │   ├── main.tf
│       │   └── variables.tf
│       ├── ec2/                  # EC2 7대 + user_data 스크립트
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── user_data/
│       │       ├── common.sh     # master용 (swap off, containerd, sysctl)
│       │       ├── worker.sh     # worker용 (common + lvm2, chrony for Ceph)
│       │       └── nsd.sh        # GPFS NSD 전용 (ksh, kernel-headers, dkms)
│       └── ebs/                  # EBS 볼륨 10개 + attachment
│           ├── main.tf           # GPFS LUN 2개 + Ceph OSD 8개(worker×2)
│           └── variables.tf
├── scripts/                      # 순차 실행 셸 스크립트
│   ├── .env                      # 00번 실행 후 자동 생성 (IP, SSH_KEY 목록)
│   ├── 00_hosts_setup.sh         # /etc/hosts 배포, 클러스터 내부 SSH 키 생성
│   ├── 01_ceph_install.sh        # rook-ceph operator + CephCluster CR + StorageClass
│   ├── 02_gpfs_install.sh        # GPFS .deb 패키지 전송 및 설치 (IBM 수동 필요)
│   ├── 03_nsd_setup.sh           # GPFS 클러스터 생성, NSD 정의, 마운트
│   ├── 04_k8s_install.sh         # kubeadm init/join, Flannel VXLAN CNI, 노드 레이블
│   ├── 05_csi_ceph.sh            # rook-ceph 상태 확인 (CSI는 rook이 자동 설치)
│   ├── 06_csi_gpfs.sh            # IBM Spectrum Scale CSI Helm 설치
│   └── 99_test_pvc.sh            # 3개 StorageClass PVC 바인딩 테스트
├── gpfs-packages/                # IBM 패키지 수동 배치 (Git 미포함)
├── storage-lab.pem               # AWS EC2 Key Pair (Git 미포함)
├── start.sh                      # 원클릭 시작 (tofu apply → hosts → k8s → rook-ceph)
├── pause.sh                      # Ceph EBS 스냅샷 후 EC2 중지
├── resume.sh                     # EC2 재시작 + .env IP 재생성
└── destroy.sh                    # 전체 AWS 리소스 영구 삭제 (tofu destroy)
```

## Windows 사용자 안내

모든 스크립트는 **Linux Bash 환경**을 전제로 작성되어 있습니다.
**Windows에서는 WSL2를 통해 실행**해야 합니다.

```powershell
# PowerShell (관리자 권한)에서 WSL2 설치
wsl --install

# 재부팅 후 WSL2 셸 진입
wsl

# 프로젝트 디렉토리로 이동
cd /mnt/c/forfun/forfun/devops/k8s-storage-lab
```

### PEM 키 준비 (WSL에서 /mnt/c/ chmod 미적용 문제)

```bash
mkdir -p ~/.ssh
cp /mnt/c/forfun/forfun/devops/k8s-storage-lab/storage-lab.pem ~/.ssh/storage-lab.pem
chmod 400 ~/.ssh/storage-lab.pem
```

스크립트는 기본적으로 `~/.ssh/storage-lab.pem`을 사용합니다.

---

## 사전 요구사항

| 항목 | 조건 | 확인 명령 |
|------|------|-----------|
| AWS CLI | v2, 자격증명 설정 완료 | `aws sts get-caller-identity` |
| OpenTofu | v1.6+ | `tofu --version` |
| jq | 설치 필요 | `jq --version` |
| kubectl | 설치 필요 | `kubectl version --client` |
| helm | v3+ | `helm version` |
| SSH Key Pair | AWS에 등록, `~/.ssh/storage-lab.pem` 배치 | — |
| GPFS 패키지 | IBM Developer Edition .deb | [IBM 다운로드](https://www.ibm.com/account/reg/us-en/signup?formid=urx-41728) |
| WSL2 (Windows) | Ubuntu 배포판 권장 | `wsl --list --verbose` |

---

## 빠른 시작

```bash
# 1. terraform.tfvars 확인
vi opentofu/terraform.tfvars   # key_name = "storage-lab"

# 2. 원클릭 시작 (인프라 + k8s + rook-ceph 자동)
bash start.sh
# → [1/5] AWS 인프라 생성 (tofu apply)
# → [2/5] 호스트 설정 (/etc/hosts, SSH 키)
# → [3/5] K8s 클러스터 구성 (kubeadm + Flannel)
# → [4/5] Ceph 클러스터 구성 (rook-ceph operator + CephCluster)
# → [5/5] GPFS 수동 안내 출력

# 3. GPFS 수동 설치 (IBM 패키지 준비 후)
#    gpfs-packages/ 에 .deb 파일 배치 후:
bash scripts/02_gpfs_install.sh
bash scripts/03_nsd_setup.sh
bash scripts/06_csi_gpfs.sh

# 4. 전체 테스트 (ceph-rbd / ceph-cephfs / gpfs-scale)
bash scripts/99_test_pvc.sh
```

---

## 운영 명령어

```bash
# 미사용 시 일시 중지 (Ceph EBS 스냅샷 후 EC2 중지)
bash pause.sh

# 재시작 (EC2 기동 + 변경된 퍼블릭 IP로 .env 자동 갱신)
bash resume.sh

# 전체 삭제 (복구 불가)
bash destroy.sh
```

---

## StorageClass 요약

| StorageClass | 백엔드 | Access Mode | 용도 |
|-------------|--------|-------------|------|
| `ceph-rbd` | Ceph RBD (rook-ceph) | RWO | 블록 스토리지 (DB, 단일 Pod) |
| `ceph-cephfs` | CephFS (rook-ceph) | RWX | 파일 공유 (다중 Pod 동시 접근) |
| `gpfs-scale` | GPFS (IBM Spectrum Scale CSI) | RWX | 고성능 병렬 파일시스템 |

---

## 설치 순서 및 의존관계

```
tofu apply
    └→ 00_hosts_setup.sh    # /etc/hosts, SSH 키
        └→ 04_k8s_install.sh    # k8s 클러스터 (rook은 k8s 위에서 실행)
            └→ 01_ceph_install.sh    # rook-ceph (k8s 필요)
                                      # ↑ 자동 실행 (start.sh)
            └→ 02_gpfs_install.sh    # GPFS 패키지 설치 (수동)
                └→ 03_nsd_setup.sh   # GPFS 클러스터/마운트 (수동)
                    └→ 06_csi_gpfs.sh    # IBM Scale CSI (수동)
                        └→ 99_test_pvc.sh    # PVC 테스트
```

## 주요 설계 결정

| 항목 | 선택 | 이유 |
|------|------|------|
| Ceph 배포 | rook-ceph (k8s operator) | HCI 환경에서 k8s 단일 제어면, CSI 자동 설치 |
| CNI | Flannel VXLAN (UDP 8472) | Calico tigera-operator는 master OOM 유발, Flannel은 DaemonSet 단일 구성으로 경량 |
| k8s 버전 | 1.29 | IBM Spectrum Scale CSI 지원 버전 상한 |
| Ceph mon | count=1 | 단일 master 환경에서 mon 3개는 API server/etcd 과부하 유발 |
| Ceph replication | size=2 | mon 1개 실습 환경 기준, size=3은 PG undersized 경고 발생 |
| master 노드 수 | 1개 | 실습 환경, etcd 쿼럼 불필요 (3개 필요 시 kubespray 고려) |
| master 인스턴스 | m5.xlarge (4 vCPU, 16GB) | t3 burstable은 rook-ceph watch 20+개 sustained 부하에서 CPU 크레딧 고갈 → apiserver/etcd crash. m5는 크레딧 없이 고정 성능 제공 |
| worker 인스턴스 | m5.large (2 vCPU, 8GB) | Ceph OSD는 24/7 sustained I/O → t3 burstable은 CPU 크레딧 고갈 위험. m5 고정 성능으로 안정적 운영 |
| nsd 인스턴스 | t3.medium (2 vCPU, 4GB) | GPFS NSD 서버 안정 운영 |
| EBS 디바이스명 | nvme1n1, nvme2n1 | t3 계열(Nitro)은 EBS를 NVMe 인터페이스로 연결 → OS에서 xvd* 아님 |
| iptables 백엔드 | iptables-legacy | Ubuntu 22.04+는 nftables 백엔드가 기본 → K8s 1.29 kube-proxy와 충돌. user_data에서 iptables-legacy로 전환 (K8s 1.31+부터 nftables 네이티브 지원) |

---

## 트러블슈팅

### kube-proxy CrashLoopBackOff (iptables nftables 충돌)

Ubuntu 22.04+는 iptables 기본 백엔드가 nftables이며, K8s 1.29 kube-proxy와 충돌합니다.
`iptables --version` 에서 `nf_tables` 가 출력되면 해당 문제입니다.

user_data(`common.sh`, `worker.sh`)에서 인스턴스 초기화 시 자동 전환되도록 설정되어 있습니다.
기존 노드에 수동 적용이 필요한 경우:

```bash
source scripts/.env
SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"

for ip in $M1_PUB $W1_PUB $W2_PUB $W3_PUB $W4_PUB; do
  ssh $SSH_OPTS ubuntu@$ip "
    sudo apt-get install -y iptables arptables ebtables
    sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
    sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
    sudo update-alternatives --set arptables /usr/sbin/arptables-legacy
    sudo update-alternatives --set ebtables /usr/sbin/ebtables-legacy
  "
done
```

---

### kube-apiserver CrashLoopBackOff / connection refused

`/var/lib/kubelet/config.yaml` 누락 또는 apiserver 크래시 루프 발생 시 전체 노드 초기화 후 재설치.

```bash
# master-1에서
sudo kubeadm reset -f
sudo rm -rf /etc/cni /etc/kubernetes /var/lib/kubelet /var/lib/etcd ~/.kube
sudo systemctl restart containerd

# worker 노드에서 (로컬에서 일괄 실행)
source scripts/.env
for ip in $W1_PUB $W2_PUB $W3_PUB $W4_PUB; do
  ssh -i ~/.ssh/storage-lab.pem ubuntu@$ip "
    sudo kubeadm reset -f
    sudo rm -rf /etc/cni /etc/kubernetes /var/lib/kubelet ~/.kube
    sudo systemctl restart containerd
  "
done

# 재설치
bash scripts/04_k8s_install.sh
```

### Flannel Pod Pending / 노드 NotReady

Flannel DaemonSet이 뜨지 않으면 수동 확인:

```bash
# master-1에서
kubectl -n kube-flannel get pods -o wide
kubectl -n kube-flannel describe pod <pod-name>

# Flannel 재적용
kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
kubectl apply  -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

### WSL에서 PEM 파일 chmod 미적용

`/mnt/c/` 경로의 파일은 WSL에서 chmod가 적용되지 않습니다. WSL 홈으로 복사 후 사용.

```bash
mkdir -p ~/.ssh
cp /mnt/c/forfun/forfun/devops/k8s-storage-lab/storage-lab.pem ~/.ssh/storage-lab.pem
chmod 400 ~/.ssh/storage-lab.pem
```

### rook-ceph operator CrashLoopBackOff (dial tcp 10.96.0.1:443: connection refused)

API server가 완전히 뜨기 전에 rook-ceph operator가 배포되면 반복 재시작됩니다.
API server 안정화 후 operator를 재시작합니다.

```bash
# API server 상태 확인
kubectl get pods -n kube-system | grep apiserver

# operator 재시작
kubectl -n rook-ceph rollout restart deployment/rook-ceph-operator

# 로그 확인
kubectl -n rook-ceph logs -l app=rook-ceph-operator -f --tail=30
```

### Ceph OSD 미생성 (worker 노드 디바이스 인식 실패)

t3 계열(Nitro 기반) 인스턴스는 EBS를 NVMe 인터페이스로 연결합니다.
`/dev/xvdb`, `/dev/xvdc`가 아닌 `/dev/nvme1n1`, `/dev/nvme2n1`로 OS에 노출됩니다.

CephCluster CR에 반드시 실제 OS 디바이스명을 지정해야 합니다:

```bash
# worker 노드에서 디바이스명 확인
lsblk | grep -v loop

# OSD 생성 상태 확인
kubectl -n rook-ceph get pods -l app=rook-ceph-osd -o wide

# CephCluster 상태 확인
kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.ceph.health}'
```

### rook-ceph로 인한 etcd/apiserver 반복 재시작

rook-ceph operator가 CRD watch 연결 20개 이상 + CSI DaemonSet 연결을 동시에 열면
단일 master 환경에서 etcd liveness probe가 timeout되어 kubelet이 etcd를 강제 재시작합니다.
etcd 재시작 → apiserver 연결 끊김 → apiserver도 재시작되는 연쇄 장애가 발생합니다.

**즉각 조치**: operator를 중지해 부하를 제거합니다.

```bash
# etcd/apiserver 재시작 반복 시 operator 즉시 중지
kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=0

# etcd 재시작 원인 확인 (SIGTERM = liveness probe 실패)
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock logs \
  $(sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps -a \
    | grep etcd | head -1 | awk '{print $1}') 2>&1 | tail -20
```

**Ceph 상태 초기화 후 재구성**:

```bash
# 1. CephCluster 삭제 (finalizer 제거)
kubectl -n rook-ceph patch cephcluster rook-ceph --type=merge \
  -p '{"metadata":{"finalizers":[]}}'
kubectl -n rook-ceph delete cephcluster rook-ceph --wait=false

# 2. CSI 리소스 정리
kubectl -n rook-ceph delete daemonset -l app=csi-cephfsplugin
kubectl -n rook-ceph delete daemonset -l app=csi-rbdplugin
kubectl -n rook-ceph delete deployment -l app=csi-cephfsplugin-provisioner
kubectl -n rook-ceph delete deployment -l app=csi-rbdplugin-provisioner

# 3. worker 노드 rook 데이터 초기화
source scripts/.env
for ip in $W1_PUB $W2_PUB $W3_PUB $W4_PUB; do
  ssh -i $SSH_KEY ubuntu@$ip "sudo rm -rf /var/lib/rook"
done

# 4. Ceph 재구성 (mon=1, sleep 포함된 스크립트 사용)
bash scripts/01_ceph_install.sh
```
