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
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
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
  source           = "./modules/ec2"
  project_name     = var.project_name
  ami_id           = data.aws_ami.ubuntu.id
  ami_frontend     = var.ami_frontend
  ami_backend      = var.ami_backend
  key_name         = var.key_name
  subnet_id        = module.vpc.subnet_id
  sg_frontend_id   = module.security_group.sg_frontend_id
  sg_backend_id    = module.security_group.sg_backend_id
  aws_region       = var.aws_region
}
