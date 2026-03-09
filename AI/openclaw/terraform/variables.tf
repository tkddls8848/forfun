variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2" # 서울
}

variable "availability_zone" {
  description = "가용 영역"
  type        = string
  default     = "ap-northeast-2a"
}

variable "instance_name" {
  description = "EC2 인스턴스 이름"
  type        = string
  default     = "openclaw"
}

# t3.large: 2 vCPU, 8GB RAM → 서울 리전 On-Demand ~$0.0928/h (~$68/월)
variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t3.large"
}

variable "ebs_volume_size" {
  description = "루트 EBS 볼륨 크기 (GB)"
  type        = number
  default     = 80
}

variable "key_pair_name" {
  description = "EC2 SSH 키 페어 이름"
  type        = string
  default     = ""
}

# SSH 접속을 허용할 IP 대역 (보안상 본인 IP로 제한 권장)
variable "allowed_ssh_cidrs" {
  description = "SSH 접속 허용 IP 목록 (CIDR)"
  type        = list(string)
  default     = ["0.0.0.0/0"] # tfvars에서 본인 IP로 제한 권장
}

# OpenClaw UI 접속을 허용할 IP 대역
variable "allowed_ui_cidrs" {
  description = "OpenClaw UI 접속 허용 IP 목록 (CIDR)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ubuntu_ami" {
  description = "Ubuntu 22.04 LTS AMI ID (서울 리전)"
  type        = string
  # aws ec2 describe-images --region ap-northeast-2 \
  #   --owners 099720109477 \
  #   --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*' \
  #   --query 'sort_by(Images,&CreationDate)[-1].ImageId'
  default = "ami-042e76978adeb8c48" # Ubuntu 22.04 LTS (서울, 2024년 기준)
}

variable "tags" {
  description = "리소스 공통 태그"
  type        = map(string)
  default = {
    Project   = "openclaw"
    ManagedBy = "terraform"
    Env       = "prod"
  }
}
