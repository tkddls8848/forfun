locals {
  bastion_user_data = file("${path.module}/user_data/bastion.sh")
  master_user_data  = file("${path.module}/user_data/common.sh")
  worker_user_data  = file("${path.module}/user_data/worker.sh")
  nsd_user_data     = file("${path.module}/user_data/nsd.sh")
}

# ── Bastion 노드 (Ansible 제어 노드) ──
resource "aws_instance" "bastion" {
  ami                    = var.ami_id
  instance_type          = "t3.small"
  key_name               = var.key_name
  subnet_id              = var.subnet_bastion_id
  vpc_security_group_ids = [var.sg_bastion_id]
  iam_instance_profile   = var.bastion_iam_profile
  user_data              = local.bastion_user_data

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-bastion"
    Role = "bastion"
  }
}

# ── Master 노드 1대 ──
resource "aws_instance" "master" {
  count                  = 1
  ami                    = var.ami_id
  instance_type          = "t3.large"
  key_name               = var.key_name
  subnet_id              = var.subnet_k8s_id
  vpc_security_group_ids = [var.sg_k8s_id]
  user_data              = local.master_user_data

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-master-1"
    Role = "master"
  }
}

# ── Worker 노드 (HCI: k8s + Ceph OSD) ──
resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = var.ami_id
  instance_type          = "m5.large"
  key_name               = var.key_name
  subnet_id              = var.subnet_k8s_id
  vpc_security_group_ids = [var.sg_k8s_id]
  user_data              = local.worker_user_data

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-worker-${count.index + 1}"
    Role = "worker"
  }
}

# ── NSD 노드 2대 (GPFS 전용) ──
resource "aws_instance" "nsd" {
  count                  = 2
  ami                    = var.ami_id
  instance_type          = "t3.large"
  key_name               = var.key_name
  subnet_id              = var.subnet_nsd_id
  vpc_security_group_ids = [var.sg_nsd_id]
  user_data              = local.nsd_user_data

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-nsd-${count.index + 1}"
    Role = "nsd"
  }
}

output "bastion_public_ip"   { value = aws_instance.bastion.public_ip }
output "master_public_ips"   { value = aws_instance.master[*].public_ip }
output "master_private_ips"  { value = aws_instance.master[*].private_ip }
output "worker_public_ips"   { value = aws_instance.worker[*].public_ip }
output "worker_private_ips"  { value = aws_instance.worker[*].private_ip }
output "worker_instance_ids" { value = aws_instance.worker[*].id }
output "nsd_public_ips"      { value = aws_instance.nsd[*].public_ip }
output "nsd_private_ips"     { value = aws_instance.nsd[*].private_ip }
output "nsd1_instance_id"    { value = aws_instance.nsd[0].id }
output "nsd2_instance_id"    { value = aws_instance.nsd[1].id }
