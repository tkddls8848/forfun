source "amazon-ebs" "frontend" {
  region        = var.aws_region
  source_ami    = var.base_ami
  instance_type = "t3.large"
  ssh_username  = "ubuntu"
  ssh_keypair_name     = var.key_name
  ssh_private_key_file = var.ssh_private_key_file
  associate_public_ip_address            = true
  temporary_security_group_source_cidrs = ["0.0.0.0/0"]

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

  provisioner "shell" {
    script          = "scripts/base.sh"
    execute_command = "sudo bash '{{.Path}}'"
  }
  provisioner "shell" {
    script          = "scripts/frontend.sh"
    execute_command = "sudo bash '{{.Path}}'"
  }
}
