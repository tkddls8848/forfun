# RGW 서비스 배포 (기본 영역 및 구역 생성)
ceph orch apply rgw s3 --port=8080 --placement="1 k8s-master"

# 사용자 생성
radosgw-admin user create --uid=s3user --display-name="S3 Test User" --system

# 액세스 키 확인
apt-get install -y jq
ACCESS_KEY=$(radosgw-admin user info --uid=s3user | jq -r '.keys[0].access_key')
SECRET_KEY=$(radosgw-admin user info --uid=s3user | jq -r '.keys[0].secret_key')

# S3 명령줄 클라이언트 설치
apt install -y awscli

# 환경 변수 설정 (위 단계에서 얻은 액세스 키와 시크릿 키 사용)
export AWS_ACCESS_KEY_ID=$ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$SECRET_KEY
export AWS_DEFAULT_REGION=default

# 테스트 버킷 생성
aws --endpoint-url http://k8s-master:8080 s3 mb s3://testbucket1

# 테스트 파일 업로드
echo "Hello S3" > test.txt
aws --endpoint-url http://k8s-master:8080 s3 cp test.txt s3://testbucket1/

# RGW 서비스 상태 확인
ceph orch ls --service_name=rgw.s3

# 버킷 목록 확인
aws --endpoint-url http://k8s-master:8080 s3 ls