output "instance_id" {
  description = "EC2 인스턴스 ID"
  value       = aws_instance.openclaw.id
}

output "instance_type" {
  description = "EC2 인스턴스 타입"
  value       = aws_instance.openclaw.instance_type
}

output "public_ip" {
  description = "Elastic IP 주소"
  value       = aws_eip.openclaw.public_ip
}

output "openclaw_ui_url" {
  description = "OpenClaw UI 접속 URL"
  value       = "http://${aws_eip.openclaw.public_ip}:18789"
}

output "ssh_command" {
  description = "SSH 접속 명령어"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_eip.openclaw.public_ip}"
}

output "security_group_id" {
  description = "Security Group ID"
  value       = aws_security_group.openclaw.id
}

output "iam_role_arn" {
  description = "Bedrock 접근용 IAM Role ARN"
  value       = aws_iam_role.openclaw.arn
}

output "setup_log" {
  description = "설치 로그 확인 명령어"
  value       = "ssh ubuntu@${aws_eip.openclaw.public_ip} 'tail -f /var/log/openclaw-setup.log'"
}

output "estimated_monthly_cost" {
  description = "예상 월 비용 (서울 리전 On-Demand 기준)"
  value = {
    ec2_t3_large    = "~$67.8/월  ($0.0928/h × 730h) → 자동 스케줄링 시 ~$11.1/월 (4h × 30일)"
    ebs_gp3_80gb    = "~$6.4/월   ($0.08/GB)"
    elastic_ip      = "~$3.6/월   (미사용 시 $0.005/h)"
    data_transfer   = "~$2~5/월   (사용량에 따라 변동)"
    lambda_free     = "$0        (월 100만 요청 무료)"
    total_scheduled = "~$23~26/월 (자동 스케줄링 활성화 시)"
    total_24x7      = "~$80~83/월 (24시간 운영 시)"
  }
}

# ══════════════════════════════════════════════════════════════════════════
# 자동 스케줄링 정보
# ══════════════════════════════════════════════════════════════════════════

output "lambda_function_name" {
  description = "Lambda 함수 이름"
  value       = aws_lambda_function.ec2_scheduler.function_name
}

output "schedule_info" {
  description = "자동 스케줄링 정보"
  value = {
    start_time_kst = "매일 오후 8시 (KST)"
    stop_time_kst  = "매일 오후 11시 55분 (KST)"
    start_time_utc = "매일 11:00 UTC"
    stop_time_utc  = "매일 14:55 UTC"
    daily_runtime  = "3시간 55분"
    status         = "활성화됨"
  }
}

output "manual_control_commands" {
  description = "수동 제어 명령어 (AWS CLI)"
  value = {
    start_instance = "aws ec2 start-instances --instance-ids ${aws_instance.openclaw.id}"
    stop_instance  = "aws ec2 stop-instances --instance-ids ${aws_instance.openclaw.id}"
    check_status   = "aws ec2 describe-instances --instance-ids ${aws_instance.openclaw.id} --query 'Reservations[0].Instances[0].State.Name'"
    invoke_lambda  = "aws lambda invoke --function-name ${aws_lambda_function.ec2_scheduler.function_name} --payload '{\"action\":\"start\"}' response.json"
  }
}
