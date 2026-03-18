.PHONY: init plan apply apply-auto destroy ssh token bedrock-setup url output fmt validate ami clean help status start stop schedule lambda-logs

TERRAFORM_DIR := opentofu
SCRIPTS_DIR   := scripts

## ── OpenTofu ───────────────────────────────────────────────────────────────

init:
	cd $(TERRAFORM_DIR) && tofu init

plan:
	cd $(TERRAFORM_DIR) && tofu plan

apply:
	cd $(TERRAFORM_DIR) && tofu apply

apply-auto:
	cd $(TERRAFORM_DIR) && tofu apply -auto-approve

destroy:
	cd $(TERRAFORM_DIR) && tofu destroy

fmt:
	cd $(TERRAFORM_DIR) && tofu fmt -recursive

validate: init
	cd $(TERRAFORM_DIR) && tofu validate

output:
	cd $(TERRAFORM_DIR) && tofu output

## ── 운영 ───────────────────────────────────────────────────────────────────

# SSH 접속
ssh:
	@IP=$$(cd $(TERRAFORM_DIR) && tofu output -raw public_ip); \
	echo "==> ssh ubuntu@$$IP"; \
	ssh -o StrictHostKeyChecking=no ubuntu@$$IP

# 설치 로그 실시간 확인
log:
	@IP=$$(cd $(TERRAFORM_DIR) && tofu output -raw public_ip); \
	ssh -o StrictHostKeyChecking=no ubuntu@$$IP 'tail -f /var/log/openclaw-setup.log'

# 게이트웨이 토큰 확인
token:
	@bash $(SCRIPTS_DIR)/show_token.sh

# Bedrock 리전 설정 적용
bedrock-setup:
	@bash $(SCRIPTS_DIR)/enable_bedrock.sh

# UI URL 출력
url:
	@cd $(TERRAFORM_DIR) && tofu output -raw openclaw_ui_url

# 예상 월 비용 출력
cost:
	@cd $(TERRAFORM_DIR) && tofu output -json estimated_monthly_cost | python3 -m json.tool

## ── 자동 스케줄링 ──────────────────────────────────────────────────────────

# 인스턴스 상태 확인
status:
	@INSTANCE_ID=$$(cd $(TERRAFORM_DIR) && tofu output -raw instance_id); \
	echo "==> 인스턴스 상태 확인: $$INSTANCE_ID"; \
	aws ec2 describe-instances --instance-ids $$INSTANCE_ID \
		--query 'Reservations[0].Instances[0].{State:State.Name,LaunchTime:LaunchTime,InstanceType:InstanceType}' \
		--output table

# 인스턴스 수동 시작
start:
	@INSTANCE_ID=$$(cd $(TERRAFORM_DIR) && tofu output -raw instance_id); \
	echo "==> 인스턴스 시작: $$INSTANCE_ID"; \
	aws ec2 start-instances --instance-ids $$INSTANCE_ID

# 인스턴스 수동 중지
stop:
	@INSTANCE_ID=$$(cd $(TERRAFORM_DIR) && tofu output -raw instance_id); \
	echo "==> 인스턴스 중지: $$INSTANCE_ID"; \
	aws ec2 stop-instances --instance-ids $$INSTANCE_ID

# 스케줄 정보 확인
schedule:
	@echo "==> 자동 스케줄링 정보"; \
	cd $(TERRAFORM_DIR) && tofu output -json schedule_info | python3 -m json.tool

# Lambda 로그 확인
lambda-logs:
	@LAMBDA_NAME=$$(cd $(TERRAFORM_DIR) && tofu output -raw lambda_function_name); \
	echo "==> Lambda 로그 확인: $$LAMBDA_NAME"; \
	aws logs tail /aws/lambda/$$LAMBDA_NAME --follow

# Lambda 함수 테스트 (시작)
lambda-test-start:
	@LAMBDA_NAME=$$(cd $(TERRAFORM_DIR) && tofu output -raw lambda_function_name); \
	echo "==> Lambda 테스트 (시작): $$LAMBDA_NAME"; \
	aws lambda invoke --function-name $$LAMBDA_NAME \
		--payload '{"action":"start"}' \
		--log-type Tail \
		response.json && cat response.json && rm response.json

# Lambda 함수 테스트 (중지)
lambda-test-stop:
	@LAMBDA_NAME=$$(cd $(TERRAFORM_DIR) && tofu output -raw lambda_function_name); \
	echo "==> Lambda 테스트 (중지): $$LAMBDA_NAME"; \
	aws lambda invoke --function-name $$LAMBDA_NAME \
		--payload '{"action":"stop"}' \
		--log-type Tail \
		response.json && cat response.json && rm response.json

## ── 유틸리티 ───────────────────────────────────────────────────────────────

# 서울 리전 최신 Ubuntu 24.04 AMI 조회
ami:
	@bash $(SCRIPTS_DIR)/get_latest_ami.sh ap-northeast-2

# .terraform 캐시 정리
clean:
	rm -rf $(TERRAFORM_DIR)/.terraform \
	       $(TERRAFORM_DIR)/terraform.tfstate.backup

help:
	@echo ""
	@echo "OpenClaw on EC2 with Auto-Scheduling — 명령어 목록"
	@echo "==================================================="
	@echo "📦 OpenTofu 배포"
	@echo "  make init          OpenTofu 초기화"
	@echo "  make plan          변경사항 미리 보기"
	@echo "  make apply         인프라 배포 (확인 필요)"
	@echo "  make apply-auto    인프라 배포 (자동 승인)"
	@echo "  make destroy       인프라 삭제"
	@echo "  make output        OpenTofu 출력값 확인"
	@echo "  make cost          예상 월 비용 출력"
	@echo ""
	@echo "🖥️  인스턴스 운영"
	@echo "  make ssh           인스턴스 SSH 접속"
	@echo "  make log           설치 로그 실시간 확인"
	@echo "  make token         OpenClaw 게이트웨이 토큰 확인"
	@echo "  make bedrock-setup Bedrock 연동 설정"
	@echo "  make url           UI 접속 URL 출력"
	@echo ""
	@echo "⏰ 자동 스케줄링"
	@echo "  make status        인스턴스 상태 확인"
	@echo "  make start         인스턴스 수동 시작"
	@echo "  make stop          인스턴스 수동 중지"
	@echo "  make schedule      스케줄 정보 확인"
	@echo "  make lambda-logs   Lambda 로그 실시간 확인"
	@echo "  make lambda-test-start  Lambda 시작 테스트"
	@echo "  make lambda-test-stop   Lambda 중지 테스트"
	@echo ""
	@echo "🔧 유틸리티"
	@echo "  make ami           서울 리전 최신 Ubuntu AMI 조회"
	@echo "  make validate      OpenTofu 코드 검증"
	@echo "  make fmt           OpenTofu 코드 포맷"
	@echo "  make clean         캐시 정리"
	@echo ""
