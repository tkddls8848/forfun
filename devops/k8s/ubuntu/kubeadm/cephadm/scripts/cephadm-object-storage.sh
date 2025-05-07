#!/bin/bash
#=========================================================================
# Ceph Object Storage (RGW) 설치 및 테스트 스크립트
# S3 API 호환 Object Storage 구성
#=========================================================================

set -e

# Object Storage 설정
export RGW_PORT=8080
export RGW_USER="s3user"
export RGW_DISPLAY_NAME="S3 Test User"
export RGW_BUCKET="testbucket"
export MASTER_HOSTNAME="k8s-master"
export MASTER_IP="192.168.56.10"

# 비대화형 설치를 위한 환경 변수 설정
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

#=========================================================================
# 1. RGW 서비스 배포
#=========================================================================
echo "[1/4] RadosGW (RGW) 서비스 배포 중..."

# 간단한 방식으로 RGW 배포
ceph orch apply rgw s3 --port=$RGW_PORT --placement="1 $MASTER_HOSTNAME"

# RGW 서비스 시작 대기
echo "RGW 서비스 배포 대기 중..."
MAX_RETRIES=20
RETRY_INTERVAL=10
count=0

while [ $count -lt $MAX_RETRIES ]; do
  if ceph orch ls --service_name=rgw.s3 | grep -q "1/1"; then
    echo "RGW 서비스 성공적으로 배포됨"
    break
  fi
  echo "RGW 배포 대기 중... ($((count+1))/$MAX_RETRIES)"
  sleep $RETRY_INTERVAL
  count=$((count+1))
done

#=========================================================================
# 2. S3 사용자 생성
#=========================================================================
echo "[2/4] S3 사용자 생성 중..."
radosgw-admin user create --uid=$RGW_USER --display-name="$RGW_DISPLAY_NAME" --system

# jq 설치 확인 (JSON 파싱용)
if ! command -v jq &> /dev/null; then
    # needrestart 임시 비활성화
    echo "jq 설치 중..."
    apt-get update
    apt-get install -y -q jq
fi

# 액세스 키 확인
ACCESS_KEY=$(radosgw-admin user info --uid=$RGW_USER | jq -r '.keys[0].access_key')
SECRET_KEY=$(radosgw-admin user info --uid=$RGW_USER | jq -r '.keys[0].secret_key')

echo "S3 사용자 생성 완료"
echo "Access Key: $ACCESS_KEY"
echo "Secret Key: <숨김>"

#=========================================================================
# 3. S3 클라이언트 선택 및 테스트
#=========================================================================
echo "[3/4] S3 클라이언트 테스트"

# Vagrant provisioning 또는 비대화형 환경 감지
if [ -n "$S3_CLIENT_CHOICE" ]; then
    CLIENT_CHOICE=$S3_CLIENT_CHOICE
    echo "환경 변수에서 선택된 클라이언트: $CLIENT_CHOICE"
elif [ ! -t 0 ] || [ -n "$VAGRANT_PROVISIONING" ]; then
    # 비대화형 환경에서는 기본값 사용
    CLIENT_CHOICE=3
    echo "비대화형 환경 감지 - 기본값 사용: 둘 다 테스트"
else
    echo "사용할 S3 클라이언트를 선택하세요:"
    echo "1) AWS CLI"
    echo "2) s3cmd"
    echo "3) 둘 다 테스트"
    
    # 입력을 기다리기 위한 명시적인 처리
    while true; do
        read -p "선택 (1-3): " CLIENT_CHOICE
        if [[ "$CLIENT_CHOICE" =~ ^[1-3]$ ]]; then
            break
        else
            echo "잘못된 입력입니다. 1, 2, 또는 3을 입력하세요."
        fi
    done
fi

echo "선택된 옵션: $CLIENT_CHOICE"

# 환경 변수 설정
export AWS_ACCESS_KEY_ID=$ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$SECRET_KEY
export AWS_DEFAULT_REGION=default

case $CLIENT_CHOICE in
  1|3)
    echo "=== AWS CLI 테스트 ==="
    if ! command -v aws &> /dev/null; then
        echo "AWS CLI 설치 중..."
        apt-get update
        apt-get install -y -q awscli
    fi
    
    # AWS CLI 설정
    aws configure set default.s3.signature_version s3v4
    aws configure set default.s3.addressing_style path
    
    # 버킷 생성
    aws --endpoint-url http://$MASTER_HOSTNAME:$RGW_PORT s3 mb s3://${RGW_BUCKET}-aws --no-verify-ssl || true
    
    # 테스트 파일 업로드
    echo "Hello S3 from AWS CLI" > test-aws.txt
    aws --endpoint-url http://$MASTER_HOSTNAME:$RGW_PORT s3 cp test-aws.txt s3://${RGW_BUCKET}-aws/ --no-verify-ssl
    
    # 버킷 목록 확인
    aws --endpoint-url http://$MASTER_HOSTNAME:$RGW_PORT s3 ls --no-verify-ssl
    ;;
esac

case $CLIENT_CHOICE in
  2|3)
    echo "=== s3cmd 테스트 ==="
    if ! command -v s3cmd &> /dev/null; then
        echo "s3cmd 설치 중..."
        apt-get update
        apt-get install -y -q s3cmd
    fi
    
    # s3cmd 설정 파일 생성
    cat > ~/.s3cfg << EOF
[default]
access_key = $ACCESS_KEY
secret_key = $SECRET_KEY
host_base = $MASTER_IP:$RGW_PORT
host_bucket = $MASTER_IP:$RGW_PORT/%(bucket)s
bucket_location = default
use_https = False
check_ssl_certificate = False
check_ssl_hostname = False
signature_v2 = True
EOF
    
    # 버킷 생성
    s3cmd mb s3://${RGW_BUCKET}-s3cmd || true
    
    # 테스트 파일 업로드
    echo "Hello S3 from s3cmd" > test-s3cmd.txt
    s3cmd put test-s3cmd.txt s3://${RGW_BUCKET}-s3cmd/
    
    # 버킷 목록 확인
    s3cmd ls
    ;;
esac

#=========================================================================
# 4. 상태 확인 및 정보 표시
#=========================================================================
echo "[4/4] Object Storage 설치 완료"
echo ""
echo "===== Object Storage 정보 ====="
echo "RGW Endpoint: http://$MASTER_HOSTNAME:$RGW_PORT"
echo "Access Key: $ACCESS_KEY"
echo "Secret Key: $SECRET_KEY"
echo ""
echo "===== 사용 예시 ====="
echo "AWS CLI:"
echo "  aws --endpoint-url http://$MASTER_HOSTNAME:$RGW_PORT s3 ls"
echo ""
echo "s3cmd:"
echo "  s3cmd ls"
echo ""
echo "===== 정리 명령어 ====="
echo "1. 버킷 삭제:"
echo "   aws --endpoint-url http://$MASTER_HOSTNAME:$RGW_PORT s3 rb s3://${RGW_BUCKET}-aws --force"
echo "   s3cmd rb s3://${RGW_BUCKET}-s3cmd"
echo "2. 사용자 삭제:"
echo "   radosgw-admin user rm --uid=$RGW_USER"
echo "3. RGW 서비스 제거:"
echo "   ceph orch rm rgw.s3"

# 환경 변수 초기화
unset DEBIAN_FRONTEND
unset NEEDRESTART_MODE
unset NEEDRESTART_SUSPEND