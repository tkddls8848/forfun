# OpenClaw on AWS EC2 with Auto-Scheduling

AWS EC2에서 OpenClaw를 자동으로 배포하고, 매일 정해진 시간에 자동으로 시작/종료되도록 구성한 OpenTofu 프로젝트입니다.

## 주요 기능

- **EC2 인스턴스**: Ubuntu 24.04 LTS 기반 t3.large (2 vCPU, 8GB RAM)
- **자동 스케줄링**: 매일 한국시간 오후 8시 시작, 오후 11시 55분 종료 (3시간 55분 운영)
- **비용 절감**: 24시간 운영 대비 약 88% 비용 절감 (~$80/월 → ~$9/월)
- **AWS Bedrock 통합**: IAM 역할을 통한 Bedrock API 접근 권한 포함
- **자동 설치**: user_data를 통한 OpenClaw 자동 설치 및 구성

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                      AWS Cloud (ap-northeast-2)              │
│                                                               │
│  ┌────────────────┐                                          │
│  │  EventBridge   │                                          │
│  │  ┌──────────┐  │                                          │
│  │  │ 20:00 UTC│──┼──┐  Start                                │
│  │  │ (05:00KST)  │  │                                       │
│  │  └──────────┘  │  │                                       │
│  │  ┌──────────┐  │  │                                       │
│  │  │ 00:00 UTC│──┼──┼──┐  Stop                              │
│  │  │ (09:00KST)  │  │  │                                    │
│  │  └──────────┘  │  │  │                                    │
│  └────────────────┘  │  │                                    │
│                      ↓  ↓                                    │
│  ┌────────────────────────────┐                              │
│  │   Lambda Function          │                              │
│  │   (EC2 Scheduler)          │                              │
│  │   - Start Instances        │                              │
│  │   - Stop Instances         │                              │
│  └────────────────────────────┘                              │
│                      │                                        │
│                      ↓                                        │
│  ┌────────────────────────────┐                              │
│  │   EC2 Instance (t3.large)  │                              │
│  │   ┌──────────────────────┐ │                              │
│  │   │  OpenClaw            │ │                              │
│  │   │  Port: 18789         │ │◄─── Elastic IP              │
│  │   │  AWS Bedrock 연동    │ │                              │
│  │   └──────────────────────┘ │                              │
│  │   Tag: AutoStart=true      │                              │
│  └────────────────────────────┘                              │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## 비용 예상

### 자동 스케줄링 활성화 (매일 4시간 운영)
- **EC2 (t3.large)**: ~$10.9/월 (3.92h × 30일 × $0.0928/h)
- **EBS (gp3 80GB)**: ~$6.4/월
- **Elastic IP**: ~$3.6/월
- **Lambda**: $0 (월 100만 요청 무료)
- **총 예상 비용**: **~$18~21/월**

### 24시간 운영 시
- **총 예상 비용**: **~$80~83/월**

**비용 절감**: 약 **75%** (연간 약 $740 절약)

## 사전 요구사항

1. **AWS CLI 설치 및 구성**
   ```bash
   aws configure
   ```

2. **OpenTofu 설치**
   ```bash
   # macOS
   brew install opentofu

   # Windows (Chocolatey 권장)
   choco install opentofu

   # Windows (Scoop)
   scoop install opentofu

   # Linux (tofuenv 권장)
   git clone https://github.com/tofuutils/tofuenv.git ~/.tofuenv
   export PATH="$HOME/.tofuenv/bin:$PATH"
   tofuenv install latest
   tofuenv use latest
   ```

3. **AWS 권한**
   - EC2, Lambda, EventBridge, IAM, VPC 리소스 생성 권한 필요

## 설치 및 배포

### 1. 설정 파일 생성

```bash
cd opentofu
cp opentofu.tfvars.example terraform.tfvars
```

`terraform.tfvars` 파일 편집:

```hcl
# 필수 설정
key_pair_name = "your-ec2-key-pair-name"  # SSH 키 페어 이름

# 선택 설정 (보안 강화)
allowed_ssh_cidrs = ["YOUR_IP_ADDRESS/32"]  # 본인 IP로 제한
allowed_ui_cidrs  = ["YOUR_IP_ADDRESS/32"]  # 본인 IP로 제한

# 인스턴스 타입 변경 (선택)
# instance_type = "t3.medium"  # 더 작은 사이즈로 변경 시
```

### 2. OpenTofu 초기화 및 배포

```bash
tofu init
tofu plan
tofu apply
```

배포 완료 후 출력 정보 확인:
```bash
tofu output
```

### 3. OpenClaw 접속

배포가 완료되면 약 5-10분 후 OpenClaw가 실행됩니다.

```bash
# OpenClaw UI 접속
http://<ELASTIC_IP>:18789

# 토큰 확인
ssh ubuntu@<ELASTIC_IP> 'grep TOKEN /home/ubuntu/.openclaw/.env'

# 설치 로그 확인
ssh ubuntu@<ELASTIC_IP> 'tail -f /var/log/openclaw-setup.log'
```

## 자동 스케줄링 관리

### 스케줄 확인

```bash
# OpenTofu output으로 확인
tofu output schedule_info
```

출력 예시:
```
{
  "start_time_kst" = "매일 오후 8시 (KST)"
  "stop_time_kst" = "매일 오후 11시 55분 (KST)"
  "daily_runtime" = "3시간 55분"
  "status" = "활성화됨"
}
```

### 수동 제어

```bash
# 인스턴스 즉시 시작
aws ec2 start-instances --instance-ids <INSTANCE_ID>

# 인스턴스 즉시 중지
aws ec2 stop-instances --instance-ids <INSTANCE_ID>

# 인스턴스 상태 확인
aws ec2 describe-instances --instance-ids <INSTANCE_ID> \
  --query 'Reservations[0].Instances[0].State.Name'

# Lambda 함수 직접 호출 (테스트)
aws lambda invoke \
  --function-name openclaw-scheduler \
  --payload '{"action":"start"}' \
  response.json
```

### 스케줄 시간 변경

`main.tf` 파일에서 EventBridge 스케줄 수정:

```hcl
# 시작 시간 변경 (예: 오전 6시 KST = 21:00 UTC)
resource "aws_cloudwatch_event_rule" "start_instance" {
  schedule_expression = "cron(0 21 * * ? *)"  # 시간 수정
}

# 중지 시간 변경 (예: 오전 10시 KST = 01:00 UTC)
resource "aws_cloudwatch_event_rule" "stop_instance" {
  schedule_expression = "cron(55 0 * * ? *)"   # 시간 수정 (분 먼저, 시간 다음)
}
```

변경 후 적용:
```bash
tofu apply
```

### 자동 스케줄링 비활성화

자동 스케줄링을 비활성화하고 24시간 운영하려면:

```bash
# EventBridge 규칙 비활성화
aws events disable-rule --name openclaw-start-schedule
aws events disable-rule --name openclaw-stop-schedule

# 인스턴스 수동 시작
aws ec2 start-instances --instance-ids <INSTANCE_ID>
```

재활성화:
```bash
aws events enable-rule --name openclaw-start-schedule
aws events enable-rule --name openclaw-stop-schedule
```

## Lambda 함수 모니터링

### CloudWatch 로그 확인

```bash
# 최근 로그 스트림 확인
aws logs tail /aws/lambda/openclaw-scheduler --follow

# 특정 날짜의 로그 확인
aws logs tail /aws/lambda/openclaw-scheduler \
  --since 1h \
  --format short
```

### Lambda 실행 이력 확인

AWS 콘솔에서:
1. Lambda 서비스 → `openclaw-scheduler` 함수 선택
2. "Monitor" 탭 → CloudWatch 메트릭 확인
3. "Logs" 탭 → 실행 로그 확인

## AWS Bedrock 사용 설정

### Bedrock 모델 액세스 활성화

1. AWS 콘솔 → Amazon Bedrock
2. "Model access" 메뉴
3. 사용할 모델 선택 (예: Claude 3.5 Sonnet)
4. "Request model access" 클릭

또는 스크립트 사용:
```bash
cd scripts
./enable_bedrock.sh
```

### OpenClaw에서 Bedrock 사용

OpenClaw UI에서:
1. Settings → AI Provider
2. "AWS Bedrock" 선택
3. 리전: `ap-northeast-2` (서울)
4. 모델: 콘솔에서 활성화된 모델 확인 후 선택
   - Claude 3.7 Sonnet: `anthropic.claude-3-7-sonnet-20250219-v1:0`
   - Claude 3.5 Sonnet v2: `anthropic.claude-3-5-sonnet-20241022-v2:0` (이전 세대)
   - 최신 모델 목록: `aws bedrock list-foundation-models --region ap-northeast-2 --by-provider Anthropic --output table`

EC2 인스턴스의 IAM 역할에 이미 Bedrock 권한이 부여되어 있어 별도의 자격 증명이 필요하지 않습니다.

## 문제 해결

### OpenClaw가 시작되지 않을 때

```bash
# 설치 로그 확인
ssh ubuntu@<ELASTIC_IP> 'tail -100 /var/log/openclaw-setup.log'

# OpenClaw 프로세스 확인
ssh ubuntu@<ELASTIC_IP> 'ps aux | grep openclaw'

# OpenClaw 재시작
ssh ubuntu@<ELASTIC_IP> 'openclaw restart'
```

### Lambda 함수가 실행되지 않을 때

```bash
# Lambda 함수 테스트
aws lambda invoke \
  --function-name openclaw-scheduler \
  --payload '{"action":"start"}' \
  --log-type Tail \
  response.json

# EventBridge 규칙 상태 확인
aws events describe-rule --name openclaw-start-schedule
aws events describe-rule --name openclaw-stop-schedule
```

### EC2 인스턴스가 자동으로 시작/중지되지 않을 때

1. **태그 확인**: EC2 인스턴스에 `AutoStart=true` 태그가 있는지 확인
   ```bash
   aws ec2 describe-instances --instance-ids <INSTANCE_ID> \
     --query 'Reservations[0].Instances[0].Tags'
   ```

2. **IAM 권한 확인**: Lambda 함수의 IAM 역할에 EC2 권한이 있는지 확인

3. **CloudWatch 로그 확인**: Lambda 실행 로그에서 오류 확인

## 리소스 정리

모든 AWS 리소스를 삭제하려면:

```bash
tofu destroy
```

⚠️ **주의**: 이 명령은 모든 리소스(EC2, Lambda, EventBridge 등)를 삭제합니다. 데이터 백업을 먼저 수행하세요.

## 프로젝트 구조

```
AI/openclaw/
├── README.md                    # 이 파일
├── Makefile                     # 편의 명령어
├── scripts/
│   ├── enable_bedrock.sh        # Bedrock 활성화 스크립트
│   ├── get_latest_ami.sh        # 최신 Ubuntu AMI 조회
│   └── show_token.sh            # OpenClaw 토큰 표시
└── opentofu/
    ├── main.tf                  # 메인 OpenTofu 구성
    ├── variables.tf             # 변수 정의
    ├── outputs.tf               # 출력 정의
    ├── versions.tf              # Provider 버전
    ├── opentofu.tfvars.example  # 설정 예시
    ├── user_data.sh.tpl         # EC2 초기화 스크립트
    └── lambda/
        ├── ec2_scheduler.py     # Lambda 함수 코드
        └── ec2_scheduler.zip    # Lambda 배포 패키지 (자동 생성)
```

## Makefile 명령어

편의를 위한 Makefile 명령어:

```bash
# 초기 설정
make init

# 배포
make apply

# 현재 상태 확인
make status

# 인스턴스 시작
make start

# 인스턴스 중지
make stop

# OpenClaw 토큰 확인
make token

# 로그 확인
make logs

# 리소스 정리
make destroy
```

## 라이선스

이 프로젝트는 MIT 라이선스로 배포됩니다.

## 참고 자료

- [OpenClaw 공식 문서](https://docs.openclaw.com/)
- [AWS Lambda 문서](https://docs.aws.amazon.com/lambda/)
- [Amazon EventBridge 문서](https://docs.aws.amazon.com/eventbridge/)
- [AWS Bedrock 문서](https://docs.aws.amazon.com/bedrock/)
- [OpenTofu Registry - AWS Provider](https://registry.opentofu.org/providers/hashicorp/aws/latest/docs)
