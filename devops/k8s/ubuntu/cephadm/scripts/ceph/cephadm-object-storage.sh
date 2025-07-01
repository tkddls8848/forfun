#!/bin/bash
#=========================================================================
# Ceph Object Storage (RGW) 설치 및 테스트 스크립트 (Podman 버전)
#=========================================================================

set -e  # 오류 발생 시 스크립트 중단

# 네트워크 인자 받기
NETWORK_PREFIX=$1
MASTER_IP=$2

# Object Storage 설정
export RGW_PORT=7480
export RGW_USER="s3user"
export RGW_DISPLAY_NAME="S3 Test User"
export RGW_BUCKET="testbucket"
export MASTER_HOSTNAME=$(hostname)  # cephadm 설치 시 지정한 hostname

# Swift 사용자 설정
export SWIFT_SUBUSER="test"  # subuser 이름만
export SWIFT_USER="$RGW_USER:$SWIFT_SUBUSER"  # 전체 Swift 사용자명
export SWIFT_USER_PASSWORD="testing"
export SWIFT_BUCKET_CONTAINER="test-container-bucket"

echo "=========================================="
echo "Ceph Object Storage 설치 시작"
echo "=========================================="
echo "RGW 포트: $RGW_PORT"
echo "마스터 호스트명: $MASTER_HOSTNAME"
echo "=========================================="

#=========================================================================
# 1. RGW 서비스 배포
#=========================================================================
echo -e "\n[단계 1/4] RadosGW (RGW) 서비스 배포 중..."

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
echo -e "\n[단계 2/4] S3 사용자 생성 중..."
radosgw-admin user create --uid=$RGW_USER --display-name="$RGW_DISPLAY_NAME"

# 액세스 키 확인
ACCESS_KEY=$(radosgw-admin user info --uid=$RGW_USER | jq -r '.keys[0].access_key')
SECRET_KEY=$(radosgw-admin user info --uid=$RGW_USER | jq -r '.keys[0].secret_key')

echo "S3 사용자 생성 완료"
echo "Access Key: $ACCESS_KEY"
echo "Secret Key: <숨김>"

# Swift 사용자 생성
echo "Swift subuser 및 key 생성 중..."
radosgw-admin subuser create --uid=$RGW_USER --subuser=$SWIFT_SUBUSER --access=full
radosgw-admin key create --subuser="$RGW_USER:$SWIFT_SUBUSER" --key-type=swift --secret="$SWIFT_USER_PASSWORD"

echo "Swift 사용자 생성 완료"

#=========================================================================
# 3. S3/Swift 클라이언트 테스트
#=========================================================================
echo -e "\n[단계 3/4] S3/Swift 클라이언트 테스트"

# Vagrant provisioning 또는 비대화형 환경 감지
if [ -n "$S3_CLIENT_CHOICE" ]; then
    CLIENT_CHOICE=$S3_CLIENT_CHOICE
    echo "환경 변수에서 선택된 클라이언트: $CLIENT_CHOICE"
else
    # 기본값 사용
    CLIENT_CHOICE=3
    echo "기본값 사용: 둘 다 테스트"
fi

echo "선택된 옵션: $CLIENT_CHOICE"

case $CLIENT_CHOICE in
  1|3)
    echo ">> s3cmd 테스트 중..."
    if ! command -v s3cmd &> /dev/null; then
        echo "s3cmd 설치 중..."
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

case $CLIENT_CHOICE in
  2|3)
    echo ">> OpenStack Swift 테스트 중..."
    if ! command -v swift &> /dev/null; then
        echo "Swift 클라이언트 설치 중..."
        apt-get install -y -q python3-swiftclient
    fi
    
    # Swift 환경 변수 설정
    export ST_AUTH=http://$MASTER_IP:$RGW_PORT/auth/v1.0
    export ST_USER=$SWIFT_USER
    export ST_KEY=$SWIFT_USER_PASSWORD
    
    # 컨테이너 생성
    ceph config set client.rgw rgw_enable_apis "s3, swift, swift_auth"
    ceph config set client.rgw rgw_swift_account_in_url true
    ceph config set client.rgw rgw_keystone_api_version 2
    swift post ${SWIFT_BUCKET_CONTAINER}
    
    # 테스트 파일 업로드
    echo "Hello Swift from OpenStack client" > test-swift.txt
    swift upload ${SWIFT_BUCKET_CONTAINER} test-swift.txt
    
    # 컨테이너 목록 확인
    swift list
    
    # 오브젝트 목록 확인
    swift list ${SWIFT_BUCKET_CONTAINER}
    ;;
esac

#=========================================================================
# 4. 상태 확인 및 정보 표시
#=========================================================================
echo -e "\n[단계 4/4] Object Storage 설치 완료"
echo ""
echo "===== Object Storage 정보 ====="
echo "RGW Endpoint: http://$MASTER_HOSTNAME:$RGW_PORT"
echo ""
echo "S3 API 접속 정보:"
echo "  Access Key: $ACCESS_KEY"
echo "  Secret Key: $SECRET_KEY"
echo ""
echo "Swift API 접속 정보:"
echo "  Auth URL: http://$MASTER_IP:$RGW_PORT/auth/v1.0"
echo "  User: $SWIFT_USER"
echo "  Password: $SWIFT_USER_PASSWORD"
echo ""
echo "===== 사용법 ====="
echo "S3 API 테스트:"
echo "  s3cmd ls"
echo "  s3cmd put <파일> s3://<버킷>/"
echo "  s3cmd get s3://<버킷>/<파일>"
echo ""
echo "Swift API 테스트:"
echo "  swift list"
echo "  swift upload <컨테이너> <파일>"
echo "  swift download <컨테이너> <파일>"
echo ""
echo "RGW 서비스 상태 확인:"
echo "  ceph orch ls --service_name=rgw.s3"
echo "  ceph -s"