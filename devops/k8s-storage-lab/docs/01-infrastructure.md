# 01. OpenTofu 인프라 코드

## 아키텍처

| 역할 | 수 | 인스턴스 | 서브넷 |
|------|----|----------|--------|
| K8s Master | 1 | m5.large | 10.0.1.0/24 |
| K8s Worker (HCI) | worker_count (기본 3) | m5.large | 10.0.1.0/24 |
| NSD (GPFS) | 2 | t3.medium | 10.0.2.0/24 |

> Worker는 K8s 컴퓨트 + Ceph OSD를 동시에 담당하는 HCI 구조.
> Ceph는 rook-ceph operator로 K8s Pod 형태로 배포됨.

---

## opentofu/main.tf

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws"; version = "~> 5.0" }
  }
}

provider "aws" { region = var.region }

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter { name = "name";               values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"] }
  filter { name = "virtualization-type"; values = ["hvm"] }
}

module "vpc" {
  source       = "./modules/vpc"
  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  region       = var.region
}

module "security_group" {
  source       = "./modules/security_group"
  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
}

module "ec2" {
  source        = "./modules/ec2"
  project_name  = var.project_name
  ami_id        = data.aws_ami.ubuntu.id
  key_name      = var.key_name
  worker_count  = var.worker_count
  subnet_k8s_id = module.vpc.subnet_k8s_id
  subnet_nsd_id = module.vpc.subnet_nsd_id
  sg_k8s_id     = module.security_group.sg_k8s_id
  sg_nsd_id     = module.security_group.sg_nsd_id
}

module "ebs" {
  source              = "./modules/ebs"
  project_name        = var.project_name
  availability_zone   = "${var.region}a"
  worker_count        = var.worker_count
  worker_instance_ids = module.ec2.worker_instance_ids
  nsd1_instance_id    = module.ec2.nsd1_instance_id
  nsd2_instance_id    = module.ec2.nsd2_instance_id
}
```

## opentofu/variables.tf

```hcl
variable "region"       { type = string; default = "ap-northeast-2" }
variable "project_name" { type = string; default = "k8s-storage-lab" }
variable "vpc_cidr"     { type = string; default = "10.0.0.0/16" }
variable "key_name"     { type = string }
variable "worker_count" { type = number }
```

## opentofu/terraform.tfvars

```hcl
key_name     = "storage-lab"   # AWS에 등록된 Key Pair 이름
worker_count = 3
```

---

## modules/vpc

서브넷 2개: k8s(10.0.1.0/24), nsd(10.0.2.0/24). IGW + 라우트 테이블 공유.

```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_subnet" "k8s" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "nsd" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
}
```

---

## modules/security_group

SG 2개: HCI(K8s+Ceph 통합), NSD.

```hcl
# HCI SG: K8s + Ceph + Flannel 포트 통합
resource "aws_security_group" "k8s" {
  ingress { from_port = 22;    to_port = 22;    protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 0;     to_port = 0;     protocol = "-1";  cidr_blocks = [var.vpc_cidr] }  # VPC 내부 전체
  egress  { from_port = 0;     to_port = 0;     protocol = "-1";  cidr_blocks = ["0.0.0.0/0"] }
}

# NSD SG: GPFS 포트
resource "aws_security_group" "nsd" {
  ingress { from_port = 22;   to_port = 22;   protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 1191; to_port = 1191; protocol = "tcp"; cidr_blocks = [var.vpc_cidr] }
  ingress { from_port = 1191; to_port = 1191; protocol = "udp"; cidr_blocks = [var.vpc_cidr] }
  ingress { from_port = 0;    to_port = 0;    protocol = "-1";  cidr_blocks = [var.vpc_cidr] }
  egress  { from_port = 0;    to_port = 0;    protocol = "-1";  cidr_blocks = ["0.0.0.0/0"] }
}
```

---

## modules/ec2

```hcl
# Master: 1대
resource "aws_instance" "master" {
  count         = 1
  instance_type = "m5.large"
  user_data     = file("${path.module}/user_data/common.sh")
}

# Worker (HCI): worker_count대
resource "aws_instance" "worker" {
  count         = var.worker_count
  instance_type = "m5.large"
  user_data     = file("${path.module}/user_data/worker.sh")
}

# NSD: 2대
resource "aws_instance" "nsd" {
  count         = 2
  instance_type = "t3.medium"
  user_data     = file("${path.module}/user_data/nsd.sh")
}
```

### user_data/common.sh (master)

```bash
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
swapoff -a && sed -i '/swap/d' /etc/fstab

# sysctl
cat <<EOF > /etc/sysctl.d/99-k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# 패키지 설치 → modules-load.d 작성 → reboot
apt-get update -y
apt-get install -y curl wget git vim jq apt-transport-https ca-certificates \
  gnupg nfs-common open-iscsi python3 python3-pip net-tools iputils-ping \
  conntrack ethtool socat containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable containerd

# modules-load.d는 패키지 설치 완료 후 작성해야 다음 부팅 시 정상 로드
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
nf_tables
nft_masq
EOF
reboot
```

### user_data/worker.sh (worker HCI)

master와 동일하되 추가 패키지 포함:

```bash
apt-get install -y ... lvm2 chrony linux-modules-extra-aws
# modules-load.d에 rbd, ceph 추가
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
nf_tables
nft_masq
rbd
ceph
EOF
reboot
```

> `linux-modules-extra-aws` 설치 후 reboot → 새 커널 기준으로 rbd/ceph 모듈 자동 로드

---

## modules/ebs

worker당 OSD EBS 2개(10GB×2), NSD당 GPFS LUN 1개(20GB).

```hcl
# Worker OSD: worker_count × 2개
resource "aws_ebs_volume" "osd_a" {
  count             = var.worker_count
  size              = 10; type = "gp3"
}
resource "aws_ebs_volume" "osd_b" {
  count             = var.worker_count
  size              = 10; type = "gp3"
}

# NSD GPFS LUN
resource "aws_ebs_volume" "gpfs_nsd1" { size = 20; type = "gp3" }
resource "aws_ebs_volume" "gpfs_nsd2" { size = 20; type = "gp3" }
```
