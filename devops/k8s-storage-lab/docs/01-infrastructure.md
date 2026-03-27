# 01. OpenTofu 인프라 코드

## 아키텍처

| 역할 | 수 | 인스턴스 | 서브넷 |
|------|----|----------|--------|
| Bastion | 1 | t3.small | 10.0.0.0/24 (public) |
| K8s Master | 1 | t3.large | 10.0.1.0/24 (private) |
| K8s Worker (HCI) | worker_count (기본 3) | m5.large | 10.0.1.0/24 (private) |
| NSD (GPFS, K8s 편입) | 2 | t3.large | 10.0.2.0/24 (private) |

> Worker는 K8s 컴퓨트 + Ceph OSD를 동시에 담당하는 HCI 구조.
> NSD 노드는 K8s 클러스터에 편입되어 taint(`role=gpfs-nsd:NoSchedule`)로 격리,
> GPFS 데몬을 privileged DaemonSet으로 실행.

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
```

---

## modules/security_group

SG 3개: Bastion / K8s HCI / NSD.

- **Bastion SG**: 외부 SSH(22), HAProxy K8s API(6443), HAProxy stats(9000)
- **K8s SG**: VPC 내부 전체 허용 + K8s/Ceph/Flannel 포트
- **NSD SG**: VPC 내부 전체 허용 + GPFS(1191), GUI(443)

---

## modules/ec2

```hcl
# Bastion: 1대 (Ansible 제어 노드 + HAProxy)
resource "aws_instance" "bastion" {
  instance_type = "t3.small"
  subnet_id     = var.subnet_bastion_id
}

# Master: 1대
resource "aws_instance" "master" {
  count         = 1
  instance_type = "t3.large"
  subnet_id     = var.subnet_k8s_id
}

# Worker (HCI): worker_count대
resource "aws_instance" "worker" {
  count         = var.worker_count
  instance_type = "m5.large"
  subnet_id     = var.subnet_k8s_id
}

# NSD: 2대 (K8s 편입 + GPFS NSD 서버)
resource "aws_instance" "nsd" {
  count         = 2
  instance_type = "t3.large"
  subnet_id     = var.subnet_nsd_id
}
```

### 인스턴스 타입 선정 근거

| 노드 | 타입 | 이유 |
|------|------|------|
| Bastion | t3.small | HAProxy + Ansible, 상시 부하 낮음 |
| Master | t3.large | control plane 실사용 ~2.5GB, m5 불필요 |
| Worker | m5.large | Ceph OSD 지속 I/O → t3 버스트 크레딧 고갈 위험 |
| NSD | t3.large | GPFS GUI(Java) + kubelet 동시 실행, 4GB OOM 위험 |

---

## modules/ebs

```hcl
# Worker OSD: worker_count × 2개 (각 10GB gp2)
resource "aws_ebs_volume" "ceph_osd_a" { count = var.worker_count; size = 10 }
resource "aws_ebs_volume" "ceph_osd_b" { count = var.worker_count; size = 10 }

# NSD GPFS LUN: NSD당 1개 (10GB gp2)
resource "aws_ebs_volume" "gpfs_nsd1" { size = 10 }
resource "aws_ebs_volume" "gpfs_nsd2" { size = 10 }
```

장치명: NSD → `/dev/xvdb`(Nitro: `/dev/nvme1n1`), Worker OSD → `/dev/xvdb`, `/dev/xvdc`

---

## user_data 스크립트

| 파일 | 대상 | 주요 내용 |
|------|------|-----------|
| `bastion.sh` | Bastion | Python, pipx, ansible-core, galaxy collections 설치 |
| `common.sh` | Master | swap off, sysctl, containerd, 커널 모듈, reboot |
| `worker.sh` | Worker | common + lvm2, chrony, linux-modules-extra-aws, rbd/ceph 모듈 |
| `nsd.sh` | NSD | common + GPFS 의존 패키지 준비 |
