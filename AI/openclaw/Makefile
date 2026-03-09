.PHONY: init plan apply apply-auto destroy ssh token bedrock-setup url output fmt validate ami clean help

TERRAFORM_DIR := terraform
SCRIPTS_DIR   := scripts

## ── Terraform ──────────────────────────────────────────────────────────────

init:
	cd $(TERRAFORM_DIR) && terraform init

plan:
	cd $(TERRAFORM_DIR) && terraform plan

apply:
	cd $(TERRAFORM_DIR) && terraform apply

apply-auto:
	cd $(TERRAFORM_DIR) && terraform apply -auto-approve

destroy:
	cd $(TERRAFORM_DIR) && terraform destroy

fmt:
	cd $(TERRAFORM_DIR) && terraform fmt -recursive

validate: init
	cd $(TERRAFORM_DIR) && terraform validate

output:
	cd $(TERRAFORM_DIR) && terraform output

## ── 운영 ───────────────────────────────────────────────────────────────────

# SSH 접속
ssh:
	@IP=$$(cd $(TERRAFORM_DIR) && terraform output -raw public_ip); \
	echo "==> ssh ubuntu@$$IP"; \
	ssh -o StrictHostKeyChecking=no ubuntu@$$IP

# 설치 로그 실시간 확인
log:
	@IP=$$(cd $(TERRAFORM_DIR) && terraform output -raw public_ip); \
	ssh -o StrictHostKeyChecking=no ubuntu@$$IP 'tail -f /var/log/openclaw-setup.log'

# 게이트웨이 토큰 확인
token:
	@bash $(SCRIPTS_DIR)/show_token.sh

# Bedrock 리전 설정 적용
bedrock-setup:
	@bash $(SCRIPTS_DIR)/enable_bedrock.sh

# UI URL 출력
url:
	@cd $(TERRAFORM_DIR) && terraform output -raw openclaw_ui_url

# 예상 월 비용 출력
cost:
	@cd $(TERRAFORM_DIR) && terraform output -json estimated_monthly_cost | python3 -m json.tool

## ── 유틸리티 ───────────────────────────────────────────────────────────────

# 서울 리전 최신 Ubuntu 22.04 AMI 조회
ami:
	@bash $(SCRIPTS_DIR)/get_latest_ami.sh ap-northeast-2

# .terraform 캐시 정리
clean:
	rm -rf $(TERRAFORM_DIR)/.terraform \
	       $(TERRAFORM_DIR)/.terraform.lock.hcl \
	       $(TERRAFORM_DIR)/terraform.tfstate.backup

help:
	@echo ""
	@echo "OpenClaw on EC2 t3.large (서울 리전) — 명령어 목록"
	@echo "=================================================="
	@echo "  make init          Terraform 초기화"
	@echo "  make plan          변경사항 미리 보기"
	@echo "  make apply         인프라 배포 (확인 필요)"
	@echo "  make apply-auto    인프라 배포 (자동 승인)"
	@echo "  make destroy       인프라 삭제"
	@echo "  make output        Terraform 출력값 확인"
	@echo "  make cost          예상 월 비용 출력"
	@echo "  ──────────────────────────────────────────────"
	@echo "  make ssh           인스턴스 SSH 접속"
	@echo "  make log           설치 로그 실시간 확인"
	@echo "  make token         OpenClaw 게이트웨이 토큰 확인"
	@echo "  make bedrock-setup Bedrock 연동 설정"
	@echo "  make url           UI 접속 URL 출력"
	@echo "  ──────────────────────────────────────────────"
	@echo "  make ami           서울 리전 최신 Ubuntu AMI 조회"
	@echo "  make validate      Terraform 코드 검증"
	@echo "  make fmt           Terraform 코드 포맷"
	@echo "  make clean         캐시 정리"
	@echo ""
