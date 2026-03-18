# 01. OpenTofu 인프라 코드

## 1. Root Module

### main.tf
```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

module "vpc" {
  source       = "./modules/vpc"
  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  aws_region   = var.aws_region
}

module "security_group" {
  source       = "./modules/security_group"
  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
}

module "ec2" {
  source         = "./modules/ec2"
  project_name   = var.project_name
  ami_id         = data.aws_ami.ubuntu.id
  key_name       = var.key_name
  subnet_k8s_id  = module.vpc.subnet_k8s_id
  subnet_nsd_id  = module.vpc.subnet_nsd_id
  subnet_ceph_id = module.vpc.subnet_ceph_id
  sg_k8s_id      = module.security_group.sg_k8s_id
  sg_nsd_id      = module.security_group.sg_nsd_id
  sg_ceph_id     = module.security_group.sg_ceph_id
}

module "ebs" {
  source            = "./modules/ebs"
  project_name      = var.project_name
  availability_zone = "${var.aws_region}a"
  nsd1_instance_id  = module.ec2.nsd1_instance_id
  nsd2_instance_id  = module.ec2.nsd2_instance_id
  ceph_instance_ids = module.ec2.ceph_instance_ids
}
```

### variables.tf
```hcl
variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "리소스 이름 prefix"
  type        = string
  default     = "k8s-storage-lab"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "key_name" {
  description = "AWS EC2 Key Pair 이름 (terraform.tfvars에서 설정)"
  type        = string
}
```

### outputs.tf
```hcl
output "master_public_ips"  { value = module.ec2.master_public_ips }
output "master_private_ips" { value = module.ec2.master_private_ips }
output "worker_public_ips"  { value = module.ec2.worker_public_ips }
output "worker_private_ips" { value = module.ec2.worker_private_ips }
output "nsd_public_ips"     { value = module.ec2.nsd_public_ips }
output "nsd_private_ips"    { value = module.ec2.nsd_private_ips }
output "ceph_public_ips"    { value = module.ec2.ceph_public_ips }
output "ceph_private_ips"   { value = module.ec2.ceph_private_ips }
output "ami_id"             { value = data.aws_ami.ubuntu.id }
```

### terraform.tfvars
```hcl
key_name     = "your-keypair-name"   # ← 본인 Key Pair 이름으로 변경
project_name = "k8s-storage-lab"
aws_region   = "ap-northeast-2"
```

---

## 2. modules/vpc

### modules/vpc/main.tf
```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "k8s" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-subnet-k8s" }
}

resource "aws_subnet" "nsd" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-subnet-nsd" }
}

resource "aws_subnet" "ceph" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-subnet-ceph" }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project_name}-rt" }
}

resource "aws_route_table_association" "k8s"  { subnet_id = aws_subnet.k8s.id;  route_table_id = aws_route_table.main.id }
resource "aws_route_table_association" "nsd"  { subnet_id = aws_subnet.nsd.id;  route_table_id = aws_route_table.main.id }
resource "aws_route_table_association" "ceph" { subnet_id = aws_subnet.ceph.id; route_table_id = aws_route_table.main.id }

output "vpc_id"        { value = aws_vpc.main.id }
output "subnet_k8s_id" { value = aws_subnet.k8s.id }
output "subnet_nsd_id" { value = aws_subnet.nsd.id }
output "subnet_ceph_id"{ value = aws_subnet.ceph.id }
```

### modules/vpc/variables.tf
```hcl
variable "project_name" { type = string }
variable "vpc_cidr"     { type = string }
variable "aws_region"   { type = string }
```

---

## 3. modules/security_group

### modules/security_group/main.tf
```hcl
# K8s SG
resource "aws_security_group" "k8s" {
  name   = "${var.project_name}-sg-k8s"
  vpc_id = var.vpc_id

  ingress { from_port = 22;    to_port = 22;    protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 6443;  to_port = 6443;  protocol = "tcp"; cidr_blocks = [var.vpc_cidr] }
  ingress { from_port = 2379;  to_port = 2380;  protocol = "tcp"; cidr_blocks = [var.vpc_cidr] }
  ingress { from_port = 10250; to_port = 10252; protocol = "tcp"; cidr_blocks = [var.vpc_cidr] }
  ingress { from_port = 30000; to_port = 32767; protocol = "tcp"; cidr_blocks = [var.vpc_cidr] }
  ingress { from_port = 179;   to_port = 179;   protocol = "tcp"; cidr_blocks = [var.vpc_cidr] }
  ingress { from_port = 4789;  to_port = 4789;  protocol = "udp"; cidr_blocks = [var.vpc_cidr] }
  ingress { from_port = 0;     to_port = 0;     protocol = "-1";  cidr_blocks = [var.vpc_cidr] }
  egress  { from_port = 0;     to_port = 0;     protocol = "-1";  cidr_blocks = ["0.0.0.0/0"] }

  tags = { Name = "${var.project_name}-sg-k8s" }
}

# Ceph SG
resource "aws_security_group" "ceph" {
  name   = "${var.project_name}-sg-ceph"
  vpc_id = var.vpc_id

  ingress { from_port = 22;   to_port = 22;   protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 6789; to_port = 6789; protocol = "tcp"; cidr_blocks = [var.vpc_cidr] }
  ingress { from_port = 3300; to_port = 3300; protocol = "tcp"; cidr_blocks = [var.vpc_cidr] }
  ingress { from_port = 6800; to_port = 7300; protocol = "tcp"; cidr_blocks = [var.vpc_cidr] }
  ingress { from_port = 8080; to_port = 8443; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0;    to_port = 0;    protocol = "-1";  cidr_blocks = ["0.0.0.0/0"] }

  tags = { Name = "${var.project_name}-sg-ceph" }
}

# NSD/GPFS SG
resource "aws_security_group" "nsd" {
  name   = "${var.project_name}-sg-nsd"
  vpc_id = var.vpc_id

  ingress { from_port = 22;   to_port = 22;   protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 1191; to_port = 1191; protocol = "tcp"; cidr_blocks = [var.vpc_cidr] }
  ingress { from_port = 1191; to_port = 1191; protocol = "udp"; cidr_blocks = [var.vpc_cidr] }
  ingress { from_port = 0;    to_port = 0;    protocol = "-1";  cidr_blocks = [var.vpc_cidr] }
  egress  { from_port = 0;    to_port = 0;    protocol = "-1";  cidr_blocks = ["0.0.0.0/0"] }

  tags = { Name = "${var.project_name}-sg-nsd" }
}

output "sg_k8s_id"  { value = aws_security_group.k8s.id }
output "sg_ceph_id" { value = aws_security_group.ceph.id }
output "sg_nsd_id"  { value = aws_security_group.nsd.id }
```

### modules/security_group/variables.tf
```hcl
variable "project_name" { type = string }
variable "vpc_id"       { type = string }
variable "vpc_cidr"     { type = string }
```

---

## 4. modules/ec2

### modules/ec2/main.tf
```hcl
locals {
  common_user_data = file("${path.module}/user_data/common.sh")
  nsd_user_data    = file("${path.module}/user_data/nsd.sh")
  ceph_user_data   = file("${path.module}/user_data/ceph.sh")
}

# ── Master 노드 3대 ──
resource "aws_instance" "master" {
  count                  = 3
  ami                    = var.ami_id
  instance_type          = "t3.medium"
  key_name               = var.key_name
  subnet_id              = var.subnet_k8s_id
  vpc_security_group_ids = [var.sg_k8s_id]
  user_data              = local.common_user_data

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-master-${count.index + 1}"
    Role = "master"
  }
}

# ── Worker 노드 3대 ──
resource "aws_instance" "worker" {
  count                  = 3
  ami                    = var.ami_id
  instance_type          = "t3.large"
  key_name               = var.key_name
  subnet_id              = var.subnet_k8s_id
  vpc_security_group_ids = [var.sg_k8s_id]
  user_data              = local.common_user_data

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-worker-${count.index + 1}"
    Role = "worker"
  }
}

# ── NSD 노드 2대 ──
resource "aws_instance" "nsd" {
  count                  = 2
  ami                    = var.ami_id
  instance_type          = "t3.medium"
  key_name               = var.key_name
  subnet_id              = var.subnet_nsd_id
  vpc_security_group_ids = [var.sg_nsd_id]
  user_data              = local.nsd_user_data

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-nsd-${count.index + 1}"
    Role = "nsd"
  }
}

# ── Ceph 노드 3대 ──
resource "aws_instance" "ceph" {
  count                  = 3
  ami                    = var.ami_id
  instance_type          = "t3.medium"
  key_name               = var.key_name
  subnet_id              = var.subnet_ceph_id
  vpc_security_group_ids = [var.sg_ceph_id]
  user_data              = local.ceph_user_data

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-ceph-${count.index + 1}"
    Role = "ceph"
  }
}

output "master_public_ips"  { value = aws_instance.master[*].public_ip }
output "master_private_ips" { value = aws_instance.master[*].private_ip }
output "worker_public_ips"  { value = aws_instance.worker[*].public_ip }
output "worker_private_ips" { value = aws_instance.worker[*].private_ip }
output "nsd_public_ips"     { value = aws_instance.nsd[*].public_ip }
output "nsd_private_ips"    { value = aws_instance.nsd[*].private_ip }
output "ceph_public_ips"    { value = aws_instance.ceph[*].public_ip }
output "ceph_private_ips"   { value = aws_instance.ceph[*].private_ip }
output "nsd1_instance_id"   { value = aws_instance.nsd[0].id }
output "nsd2_instance_id"   { value = aws_instance.nsd[1].id }
output "ceph_instance_ids"  { value = aws_instance.ceph[*].id }
```

### modules/ec2/variables.tf
```hcl
variable "project_name"   { type = string }
variable "ami_id"         { type = string }
variable "key_name"       { type = string }
variable "subnet_k8s_id"  { type = string }
variable "subnet_nsd_id"  { type = string }
variable "subnet_ceph_id" { type = string }
variable "sg_k8s_id"      { type = string }
variable "sg_nsd_id"      { type = string }
variable "sg_ceph_id"     { type = string }
```

### modules/ec2/user_data/common.sh
```bash
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

swapoff -a
sed -i '/swap/d' /etc/fstab

cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<EOF > /etc/sysctl.d/99-k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

apt-get update -y
apt-get install -y \
  curl wget git vim jq \
  apt-transport-https ca-certificates gnupg \
  nfs-common open-iscsi \
  python3 python3-pip \
  net-tools iputils-ping

apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd
```

### modules/ec2/user_data/nsd.sh
```bash
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

swapoff -a
sed -i '/swap/d' /etc/fstab

apt-get update -y
apt-get install -y \
  curl wget vim jq \
  ksh perl \
  python3 python3-pip \
  libaio1 libssl-dev \
  net-tools iputils-ping \
  build-essential \
  linux-headers-$(uname -r)

apt-get install -y dkms

echo "NSD node bootstrap complete - GPFS install required manually"
```

### modules/ec2/user_data/ceph.sh
```bash
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

swapoff -a
sed -i '/swap/d' /etc/fstab

apt-get update -y
apt-get install -y \
  curl wget vim jq \
  python3 python3-pip \
  lvm2 \
  net-tools iputils-ping \
  chrony

systemctl enable --now chrony

apt-get install -y docker.io || true
systemctl enable --now docker || true

echo "Ceph node bootstrap complete - cephadm install in 01_ceph_install.sh"
```

---

## 5. modules/ebs

### modules/ebs/main.tf
```hcl
# ── GPFS LUN: NSD-1용 ──
resource "aws_ebs_volume" "gpfs_nsd1" {
  availability_zone = var.availability_zone
  size              = 10
  type              = "gp2"
  tags              = { Name = "${var.project_name}-gpfs-lun-nsd1" }
}

resource "aws_volume_attachment" "gpfs_nsd1" {
  device_name  = "/dev/xvdb"
  volume_id    = aws_ebs_volume.gpfs_nsd1.id
  instance_id  = var.nsd1_instance_id
  force_detach = true
}

# ── GPFS LUN: NSD-2용 ──
resource "aws_ebs_volume" "gpfs_nsd2" {
  availability_zone = var.availability_zone
  size              = 10
  type              = "gp2"
  tags              = { Name = "${var.project_name}-gpfs-lun-nsd2" }
}

resource "aws_volume_attachment" "gpfs_nsd2" {
  device_name  = "/dev/xvdb"
  volume_id    = aws_ebs_volume.gpfs_nsd2.id
  instance_id  = var.nsd2_instance_id
  force_detach = true
}

# ── Ceph OSD: 노드당 2개 × 3노드 = 6개 ──
resource "aws_ebs_volume" "ceph_osd_a" {
  count             = 3
  availability_zone = var.availability_zone
  size              = 20
  type              = "gp2"
  tags              = { Name = "${var.project_name}-ceph-osd-${count.index + 1}-a" }
}

resource "aws_ebs_volume" "ceph_osd_b" {
  count             = 3
  availability_zone = var.availability_zone
  size              = 20
  type              = "gp2"
  tags              = { Name = "${var.project_name}-ceph-osd-${count.index + 1}-b" }
}

resource "aws_volume_attachment" "ceph_osd_a" {
  count        = 3
  device_name  = "/dev/xvdb"
  volume_id    = aws_ebs_volume.ceph_osd_a[count.index].id
  instance_id  = var.ceph_instance_ids[count.index]
  force_detach = true
}

resource "aws_volume_attachment" "ceph_osd_b" {
  count        = 3
  device_name  = "/dev/xvdc"
  volume_id    = aws_ebs_volume.ceph_osd_b[count.index].id
  instance_id  = var.ceph_instance_ids[count.index]
  force_detach = true
}
```

### modules/ebs/variables.tf
```hcl
variable "project_name"      { type = string }
variable "availability_zone" { type = string }
variable "nsd1_instance_id"  { type = string }
variable "nsd2_instance_id"  { type = string }
variable "ceph_instance_ids" { type = list(string) }
```