variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "리소스 이름 prefix"
  type        = string
  default     = "k3s-storage-lab"
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
