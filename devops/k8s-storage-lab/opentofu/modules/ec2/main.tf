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
