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
    ec2_t3_large    = "~$67.8/월  ($0.0928/h × 730h)"
    ebs_gp3_80gb    = "~$6.4/월   ($0.08/GB)"
    elastic_ip      = "~$3.6/월   (미사용 시 $0.005/h)"
    data_transfer   = "~$2~5/월   (사용량에 따라 변동)"
    total_estimated = "~$80~83/월"
  }
}
