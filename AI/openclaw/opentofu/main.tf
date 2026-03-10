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

  tags = merge(var.tags, {
    Name      = var.instance_name
    AutoStart = "true" # Lambda 함수가 이 태그로 인스턴스를 식별
  })

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

# ══════════════════════════════════════════════════════════════════════════
# EC2 자동 스케줄링 (매일 한국시간 오전 5시 시작, 오전 9시 종료)
# ══════════════════════════════════════════════════════════════════════════

# ── Lambda IAM 역할 ────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda_scheduler" {
  name = "${var.instance_name}-lambda-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# Lambda가 EC2를 제어할 수 있는 정책
resource "aws_iam_role_policy" "lambda_ec2_control" {
  name = "${var.instance_name}-lambda-ec2-policy"
  role = aws_iam_role.lambda_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StartInstances",
          "ec2:StopInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ── Lambda 함수 ────────────────────────────────────────────────────────────
data "archive_file" "lambda_scheduler" {
  type        = "zip"
  source_file = "${path.module}/lambda/ec2_scheduler.py"
  output_path = "${path.module}/lambda/ec2_scheduler.zip"
}

resource "aws_lambda_function" "ec2_scheduler" {
  filename         = data.archive_file.lambda_scheduler.output_path
  function_name    = "${var.instance_name}-scheduler"
  role             = aws_iam_role.lambda_scheduler.arn
  handler          = "ec2_scheduler.lambda_handler"
  source_code_hash = data.archive_file.lambda_scheduler.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60

  tags = merge(var.tags, { Name = "${var.instance_name}-scheduler" })
}

# ── EventBridge 스케줄러 ───────────────────────────────────────────────────
# 한국시간 오후 8시 = UTC 11시 → 매일 11:00 UTC에 시작
resource "aws_cloudwatch_event_rule" "start_instance" {
  name                = "${var.instance_name}-start-schedule"
  description         = "Start OpenClaw instance at 8 PM KST (11 AM UTC)"
  schedule_expression = "cron(0 11 * * ? *)"

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "start_instance" {
  rule      = aws_cloudwatch_event_rule.start_instance.name
  target_id = "StartInstance"
  arn       = aws_lambda_function.ec2_scheduler.arn

  input = jsonencode({
    action = "start"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_start" {
  statement_id  = "AllowExecutionFromEventBridgeStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_instance.arn
}

# 한국시간 오후 11시 55분 = UTC 14시 55분 → 매일 14:55 UTC에 중지
resource "aws_cloudwatch_event_rule" "stop_instance" {
  name                = "${var.instance_name}-stop-schedule"
  description         = "Stop OpenClaw instance at 11:55 PM KST (2:55 PM UTC)"
  schedule_expression = "cron(55 14 * * ? *)"

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "stop_instance" {
  rule      = aws_cloudwatch_event_rule.stop_instance.name
  target_id = "StopInstance"
  arn       = aws_lambda_function.ec2_scheduler.arn

  input = jsonencode({
    action = "stop"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_stop" {
  statement_id  = "AllowExecutionFromEventBridgeStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_instance.arn
}
