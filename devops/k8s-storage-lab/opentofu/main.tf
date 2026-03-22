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
  source        = "./modules/ec2"
  project_name  = var.project_name
  ami_id        = data.aws_ami.ubuntu.id
  key_name      = var.key_name
  subnet_k8s_id = module.vpc.subnet_k8s_id
  subnet_nsd_id = module.vpc.subnet_nsd_id
  sg_k8s_id     = module.security_group.sg_k8s_id
  sg_nsd_id     = module.security_group.sg_nsd_id
}

module "ebs" {
  source              = "./modules/ebs"
  project_name        = var.project_name
  availability_zone   = "${var.aws_region}a"
  nsd1_instance_id    = module.ec2.nsd1_instance_id
  nsd2_instance_id    = module.ec2.nsd2_instance_id
  worker_instance_ids = module.ec2.worker_instance_ids
}
