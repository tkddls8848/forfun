###############################################################################
# OpenClaw on AWS EC2 t3.large — 서울 리전 (ap-northeast-2)
# On-Demand: ~$0.0928/h → 약 $68/월 (EBS, EIP 포함 시 ~$78/월)
###############################################################################

# ── 데이터 소스 ────────────────────────────────────────────────────────────
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "availabilityZone"
    values = [var.availability_zone]
  }
}

# ── Security Group ─────────────────────────────────────────────────────────
resource "aws_security_group" "openclaw" {
  name        = "${var.instance_name}-sg"
  description = "OpenClaw EC2 security group"
  vpc_id      = data.aws_vpc.default.id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # OpenClaw UI
  ingress {
    description = "OpenClaw UI"
    from_port   = 18789
    to_port     = 18789
    protocol    = "tcp"
    cidr_blocks = var.allowed_ui_cidrs
  }

  # HTTPS (nginx 리버스 프록시 선택적 사용)
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.instance_name}-sg" })
}

# ── IAM: Bedrock 접근용 Instance Profile ──────────────────────────────────
resource "aws_iam_role" "openclaw" {
  name = "${var.instance_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "openclaw_bedrock" {
  name = "${var.instance_name}-bedrock-policy"
  role = aws_iam_role.openclaw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListFoundationModels",
          "bedrock:GetFoundationModel"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "openclaw" {
  name = "${var.instance_name}-profile"
  role = aws_iam_role.openclaw.name
}

# ── EC2 인스턴스 ───────────────────────────────────────────────────────────
resource "aws_instance" "openclaw" {
  ami                    = var.ubuntu_ami
  instance_type          = var.instance_type   # t3.large (2 vCPU, 8GB RAM)
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids = [aws_security_group.openclaw.id]
  iam_instance_profile   = aws_iam_instance_profile.openclaw.name
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.ebs_volume_size # 80GB
    delete_on_termination = true
    encrypted             = true

    tags = merge(var.tags, { Name = "${var.instance_name}-root" })
  }

  # T3 무제한 크레딧 모드 비활성화 (예상치 못한 과금 방지)
  credit_specification {
    cpu_credits = "standard"
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    instance_name = var.instance_name
  }))

  tags = merge(var.tags, { Name = var.instance_name })

  lifecycle {
    ignore_changes = [user_data, ami]
  }
}

# ── Elastic IP ─────────────────────────────────────────────────────────────
resource "aws_eip" "openclaw" {
  instance = aws_instance.openclaw.id
  domain   = "vpc"

  tags = merge(var.tags, { Name = "${var.instance_name}-eip" })
}
