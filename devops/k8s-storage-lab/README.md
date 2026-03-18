# K8s Storage Lab

AWS 위에 Kubernetes + Ceph + IBM Spectrum Scale(GPFS) 스토리지 통합 실습 환경을 자동 구성하는 프로젝트입니다.

## 아키텍처 개요

| 역할 | 노드 수 | 인스턴스 | 서브넷 | 주요 구성 |
|------|---------|----------|--------|-----------|
| K8s Master | 3 | t3.medium | 10.0.1.0/24 | kubeadm HA, etcd, Calico |
| K8s Worker | 3 | t3.large | 10.0.1.0/24 | 워크로드 실행, CSI 마운트 |
| NSD (GPFS) | 2 | t3.medium | 10.0.2.0/24 | Spectrum Scale NSD 서버 |
| Ceph | 3 | t3.medium | 10.0.3.0/24 | cephadm, OSD×2, CephFS, RBD |

**총 11대 EC2** / EBS: GPFS LUN 2개 + Ceph OSD 6개

## 디렉토리 구조
```
k8s-storage-lab/
├── opentofu/                     # IaC (OpenTofu)
│   ├── main.tf                   # 루트 모듈 — provider, data, module 호출
│   ├── variables.tf              # 전역 변수 (region, project_name, vpc_cidr, key_name)
│   ├── outputs.tf                # 전체 IP 출력
│   ├── terraform.tfvars          # ← key_name 등 실제 값 설정
│   └── modules/
│       ├── vpc/                  # VPC, 서브넷 3개, IGW, 라우트 테이블
│       │   ├── main.tf
│       │   └── variables.tf
│       ├── security_group/       # K8s / NSD / Ceph 전용 SG
│       │   ├── main.tf
│       │   └── variables.tf
│       ├── ec2/                  # EC2 11대 + user_data 스크립트
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── user_data/
│       │       ├── common.sh     # K8s 노드 공통 (swap off, containerd, sysctl)
│       │       ├── nsd.sh        # GPFS NSD 전용 (ksh, kernel-headers, dkms)
│       │       └── ceph.sh       # Ceph 전용 (docker, chrony)
│       └── ebs/                  # EBS 볼륨 8개 + attachment
│           ├── main.tf
│           └── variables.tf
├── scripts/                      # 순차 실행 셸 스크립트
│   ├── .env                      # 00번 실행 후 자동 생성 (IP 목록)
│   ├── 00_hosts_setup.sh         # /etc/hosts, SSH 키 배포
│   ├── 01_ceph_install.sh        # cephadm bootstrap, OSD, CephFS, RBD pool
│   ├── 02_gpfs_install.sh        # GPFS .deb 패키지 전송 및 설치
│   ├── 03_nsd_setup.sh           # GPFS 클러스터 생성, NSD 정의, 마운트
│   ├── 04_k8s_install.sh         # kubeadm HA init/join, Calico CNI
│   ├── 05_csi_ceph.sh            # ceph-csi-rbd + ceph-csi-cephfs Helm 설치
│   ├── 06_csi_gpfs.sh            # IBM Spectrum Scale CSI Helm 설치
│   └── 99_test_pvc.sh            # 3개 StorageClass PVC 바인딩 테스트
├── gpfs-packages/                # IBM 패키지 수동 배치 (Git 미포함)
├── start.sh                      # 원클릭 시작 (tofu apply → hosts → ceph)
└── stop.sh                       # 중지/삭제 (snapshot | destroy)
```

## Windows 사용자 안내

이 프로젝트의 모든 스크립트(`start.sh`, `stop.sh`, `scripts/*.sh`)는 **Linux Bash 환경**을 전제로 작성되어 있습니다.
**Windows에서는 WSL2(Windows Subsystem for Linux)를 통해 실행**해야 합니다.

### WSL2 설치 및 실행 방법

```powershell
# 1. PowerShell (관리자 권한)에서 WSL2 설치
wsl --install

# 2. 재부팅 후 Ubuntu 배포판 실행
wsl

# 3. WSL2 셸에서 프로젝트 디렉토리로 이동
cd /mnt/c/forfun/forfun/devops/k8s-storage-lab

# 4. 이후 모든 작업은 WSL2 셸 내에서 진행
```

> WSL2가 이미 설치되어 있다면 `wsl --list --verbose` 로 배포판을 확인하세요.
> GPFS 패키지(`.deb` 추출 포함)도 WSL2 셸에서 실행해야 합니다.

---

## 사전 요구사항

| 항목 | 조건 | 확인 명령 |
|------|------|-----------|
| AWS CLI | v2 설정 완료 | `aws sts get-caller-identity` |
| OpenTofu | v1.6+ | `tofu --version` |
| jq | 설치 필요 | `jq --version` |
| SSH Key Pair | AWS에 등록된 키 | AWS Console → EC2 → Key Pairs |
| GPFS 패키지 | IBM Developer Edition .deb | [다운로드 링크](https://www.ibm.com/account/reg/us-en/signup?formid=urx-41728) |
| **WSL2** (Windows만 해당) | Ubuntu 배포판 권장 | `wsl --list --verbose` |

## 빠른 시작
```bash
# 1. terraform.tfvars 수정
cd opentofu/
vi terraform.tfvars   # key_name = "your-keypair-name"

# 2. 원클릭 시작 (인프라 + Ceph)
cd ..
SSH_KEY_PATH=~/.ssh/your-key.pem ./start.sh

# 3. GPFS 수동 설치 (IBM 패키지 필요)
bash scripts/02_gpfs_install.sh
bash scripts/03_nsd_setup.sh

# 4. K8s 클러스터 + CSI
bash scripts/04_k8s_install.sh
bash scripts/05_csi_ceph.sh
bash scripts/06_csi_gpfs.sh

# 5. 테스트
bash scripts/99_test_pvc.sh

# 6. 종료
./stop.sh snapshot   # EC2 중지 (EBS 보존)
./stop.sh destroy    # 전체 삭제
```

## StorageClass 요약

| StorageClass | 백엔드 | Access Mode | 용도 |
|-------------|--------|-------------|------|
| `ceph-rbd` | Ceph RBD | RWO | 블록 스토리지 (DB, 단일 Pod) |
| `ceph-cephfs` | CephFS | RWX | 파일 공유 (다중 Pod 동시 접근) |
| `gpfs-scale` | GPFS | RWX | 고성능 병렬 파일시스템 |

## 상세 문서

- [docs/01-infrastructure.md](docs/01-infrastructure.md) — OpenTofu 전체 코드 (VPC, SG, EC2, EBS)
- [docs/02-scripts.md](docs/02-scripts.md) — 셸 스크립트 전체 코드 (00~99번)
- [docs/03-execution-guide.md](docs/03-execution-guide.md) — 단계별 실행 가이드
- [docs/04-troubleshooting.md](docs/04-troubleshooting.md) — 트러블슈팅 및 FAQ