# 02. Packer AMI 빌드 가이드

## 목적

매 배포 시 반복되는 패키지 설치를 AMI에 사전 굽기하여
`start.sh` 전체 구성 시간을 단축합니다.

| 구분 | 기존 | Packer AMI 적용 후 |
|---|---|---|
| Phase 2 k3s frontend 구성 | ~5분 | ~2분 (서비스 등록/조인만) |
| Phase 3 Ceph backend 구성 | ~5분 | ~3분 (bootstrap만) |
| Phase 4 BeeGFS backend 구성 | ~5분 | ~2분 (conf/서비스만) |
| **합계** | **~15분** | **~7분** |

> k8s-storage-lab 대비 절감 폭이 작은 이유: BeeGFS 커널 모듈을 DKMS로 빌드하므로
> 커널 버전이 고정된 AMI에 포함 가능하나, cephadm bootstrap은 런타임에서만 가능.

---

## 디렉토리 구조
```
packer/k3s-storage-lab/
├── frontend.pkr.hcl
├── backend.pkr.hcl
├── variables.pkrvars.hcl
└── scripts/
    ├── base.sh        # 공통 (swap off, 커널 고정, 커널 모듈, sysctl)
    ├── frontend.sh    # k3s 바이너리 설치 (서비스 등록 X)
    └── backend.sh     # cephadm, BeeGFS 7.4.6 패키지, nvme-cli, xfsprogs
```

---

## AMI 레이어 설계

### k3s-frontend AMI

| 포함 (AMI) | 제외 (런타임 스크립트) |
|---|---|
| k3s 바이너리 (v1.31.6+k3s1) | k3s server 서비스 등록 |
| 커널 모듈 (overlay, br_netfilter) | k3s-agent1 / k3s-agent2 서비스 등록 |
| swap off, sysctl 설정 | K3S_TOKEN 기반 join |
| 커널 고정 | kubeconfig 생성 |

### k3s-backend AMI

| 포함 (AMI) | 제외 (런타임 스크립트) |
|---|---|
| cephadm 바이너리 | cephadm bootstrap (mon-ip 필요) |
| podman | OSD 추가 |
| BeeGFS 7.4.6 패키지 (mgmtd, meta, storage, utils) | BeeGFS conf 파일 |
| nvme-cli, xfsprogs, lvm2 | 서비스 등록 |
| 커널 고정 | |

---

## Packer 파일

### `frontend.pkr.hcl`
```hcl
packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "aws_region" { default = "ap-northeast-2" }
variable "base_ami"   { description = "Ubuntu 24.04 AMI ID" }
variable "key_name"   { description = "EC2 Key Pair 이름" }
variable "subnet_id"  { description = "Packer 빌드용 public subnet ID" }

source "amazon-ebs" "frontend" {
  region        = var.aws_region
  source_ami    = var.base_ami
  instance_type = "t3.large"
  ssh_username  = "ubuntu"
  key_pair      = var.key_name
  subnet_id     = var.subnet_id
  associate_public_ip_address = true

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ami_name        = "k3s-storage-lab-frontend-{{timestamp}}"
  ami_description = "k3s frontend: k3s v1.31.6+k3s1 binary (Ubuntu 24.04)"

  tags = {
    Project   = "k3s-storage-lab"
    Role      = "frontend"
    OS        = "ubuntu-24.04"
    k3s       = "v1.31.6+k3s1"
    BuildDate = "{{timestamp}}"
  }
}

build {
  sources = ["source.amazon-ebs.frontend"]

  provisioner "shell" { script = "scripts/base.sh" }
  provisioner "shell" { script = "scripts/frontend.sh" }
}
```

### `backend.pkr.hcl`
```hcl
source "amazon-ebs" "backend" {
  region        = var.aws_region
  source_ami    = var.base_ami
  instance_type = "t3.medium"
  ssh_username  = "ubuntu"
  key_pair      = var.key_name
  subnet_id     = var.subnet_id
  associate_public_ip_address = true

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ami_name        = "k3s-storage-lab-backend-{{timestamp}}"
  ami_description = "k3s backend: cephadm + BeeGFS 7.4.6 packages (Ubuntu 24.04)"

  tags = {
    Project   = "k3s-storage-lab"
    Role      = "backend"
    OS        = "ubuntu-24.04"
    BeeGFS    = "7.4.6"
    BuildDate = "{{timestamp}}"
  }
}

build {
  sources = ["source.amazon-ebs.backend"]

  provisioner "shell" { script = "scripts/base.sh" }
  provisioner "shell" { script = "scripts/backend.sh" }
}
```

### `variables.pkrvars.hcl`
```hcl
aws_region = "ap-northeast-2"
base_ami   = "ami-xxxxxxxx"    # Ubuntu 24.04 LTS (Canonical)
key_name   = "storage-lab"
subnet_id  = "subnet-xxxxxxxx" # public subnet (인터넷 접근 필요)
```

---

## 빌드 스크립트

### `scripts/base.sh`
```bash
#!/bin/bash
set -e

# swap off
swapoff -a
sed -i '/swap/d' /etc/fstab

# 커널 고정
apt-mark hold linux-image-* linux-headers-* 2>/dev/null || true

# 공통 패키지
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y curl ca-certificates gnupg

# 커널 모듈
modprobe overlay br_netfilter
cat > /etc/modules-load.d/k3s.conf <<EOF
overlay
br_netfilter
EOF

# sysctl
cat > /etc/sysctl.d/99-k3s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system
```

### `scripts/frontend.sh`
```bash
#!/bin/bash
set -e

K3S_VERSION="v1.31.6+k3s1"

# k3s 바이너리만 다운로드 (서비스 등록 X)
# INSTALL_K3S_SKIP_START=true: 설치 후 서비스 시작 안 함
# INSTALL_K3S_SKIP_ENABLE=true: systemd enable 안 함
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  INSTALL_K3S_SKIP_START=true \
  INSTALL_K3S_SKIP_ENABLE=true \
  sh -

echo "✅ k3s 바이너리 설치 완료 (서비스 등록 제외)"
k3s --version
```

### `scripts/backend.sh`
```bash
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# cephadm 의존성
apt-get update -qq
apt-get install -y python3 podman nvme-cli lvm2 xfsprogs

# cephadm 설치
apt-get install -y cephadm

# BeeGFS 7.4.6 저장소
wget -q https://www.beegfs.io/release/beegfs_7.4.6/gpg/GPG-KEY-beegfs \
  -O- | gpg --dearmor > /etc/apt/trusted.gpg.d/beegfs.gpg
echo "deb https://www.beegfs.io/release/beegfs_7.4.6/ noble non-free" \
  > /etc/apt/sources.list.d/beegfs.list
apt-get update -qq

# BeeGFS 서버 패키지 (클라이언트 제외 — frontend EC2에서만 필요)
apt-get install -y \
  beegfs-mgmtd \
  beegfs-meta \
  beegfs-storage \
  beegfs-utils

echo "✅ backend AMI 패키지 설치 완료"
```

---

## OpenTofu 연동

`opentofu/modules/ec2/variables.tf` 변경:
```hcl
variable "ami_frontend" { description = "Packer k3s-frontend AMI ID" }
variable "ami_backend"  { description = "Packer k3s-backend AMI ID" }
```

`opentofu/modules/ec2/main.tf`:
```hcl
resource "aws_instance" "frontend" {
  ami       = var.ami_frontend
  # user_data 제거 (AMI에 포함)
  ...
}

resource "aws_instance" "backend" {
  ami       = var.ami_backend
  # user_data 제거 (AMI에 포함)
  ...
}
```

`opentofu/terraform.tfvars`:
```hcl
ami_frontend = "ami-0aaa..."   # packer build frontend 출력값
ami_backend  = "ami-0bbb..."   # packer build backend 출력값
```

---

## start.sh 연동
```bash
# start.sh 상단에 플래그 추가
USE_PACKER_AMI=${USE_PACKER_AMI:-false}

# Phase 2: k3s frontend 구성
if [ "$USE_PACKER_AMI" = "true" ]; then
  # 바이너리 설치 단계 스킵 — 서비스 등록/조인만 실행
  ssh $SSH_OPTS ubuntu@$FRONTEND_IP 'sudo bash -s' < scripts/01_k3s_frontend_join.sh
else
  ssh $SSH_OPTS ubuntu@$FRONTEND_IP 'sudo bash -s' < scripts/01_k3s_frontend.sh
fi

# Phase 3+4: backend 구성
if [ "$USE_PACKER_AMI" = "true" ]; then
  # 패키지 설치 단계 스킵 — bootstrap/conf만 실행
  ssh $SSH_OPTS ubuntu@$BACKEND_IP 'sudo bash -s' < scripts/02_ceph_bootstrap_only.sh
  ssh $SSH_OPTS ubuntu@$BACKEND_IP 'sudo bash -s' < scripts/03_beegfs_conf_only.sh
else
  ssh $SSH_OPTS ubuntu@$BACKEND_IP 'sudo bash -s' < scripts/02_ceph_backend.sh
  ssh $SSH_OPTS ubuntu@$BACKEND_IP 'sudo bash -s' < scripts/03_beegfs_backend.sh
fi
```

실행:
```bash
# Packer AMI 사용
USE_PACKER_AMI=true bash start.sh

# 기존 방식
bash start.sh
```

---

## 빌드 및 운영 절차

### 최초 AMI 빌드
```bash
cd packer/k3s-storage-lab

# Ubuntu 24.04 최신 AMI ID 확인
aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
  --output text

# variables 수정
vi variables.pkrvars.hcl

# 빌드
packer init .
packer build -var-file=variables.pkrvars.hcl frontend.pkr.hcl
packer build -var-file=variables.pkrvars.hcl backend.pkr.hcl
```

### AMI 갱신 기준

| 상황 | 갱신 필요 여부 |
|---|---|
| k3s 버전 업그레이드 | ✅ frontend |
| BeeGFS 버전 업그레이드 | ✅ backend |
| Ceph 버전 업그레이드 | ✅ backend (cephadm) |
| Ubuntu 보안 패치 | ✅ 전체 (월 1회 권장) |
| 스크립트 로직 변경만 | ❌ 불필요 |

---

## k8s-storage-lab과의 차이점

| 항목 | k8s-storage-lab | k3s-storage-lab |
|---|---|---|
| AMI 수 | 3개 (bastion/master/worker) | 2개 (frontend/backend) |
| 최대 절감 항목 | BeeGFS 커널 모듈 빌드 (~5분) | 패키지 설치 (~3분) |
| Ansible 사용 | ✅ (role 기반) | ❌ (shell 스크립트) |
| 런타임 분리 스크립트 필요 | `--skip-tags` 플래그 | `*_join.sh`, `*_conf_only.sh` 별도 작성 |