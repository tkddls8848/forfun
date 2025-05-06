# RGW 서비스 배포 (기본 영역 및 구역 생성)
ceph orch apply rgw s3 --port=8080 --placement="1 k8s-master"

# 사용자 생성
radosgw-admin user create --uid=s3user --display-name="S3 Test User" --system

# 액세스 키 확인
apt-get install -y jq
ACCESS_KEY=$(radosgw-admin user info --uid=s3user | jq -r '.keys[0].access_key')
SECRET_KEY=$(radosgw-admin user info --uid=s3user | jq -r '.keys[0].secret_key')

# s3cmd 설치
apt install -y s3cmd

# 설정 파일 재생성 - IP 주소 사용
cat > ~/.s3cfg << EOF
[default]
access_key = $ACCESS_KEY
secret_key = $SECRET_KEY
host_base = 192.168.56.10:8080
host_bucket = 192.168.56.10:8080/%(bucket)s
bucket_location = default
use_https = False
check_ssl_certificate = False
check_ssl_hostname = False
signature_v2 = True
EOF

# 버킷 생성
s3cmd mb s3://mybucket2

# 버킷 목록 확인
s3cmd ls

# 파일 업로드
echo "Hello S3 from s3cmd" > test_s3cmd.txt
s3cmd put test_s3cmd.txt s3://mybucket2/

# 버킷 내의 객체 목록 확인
s3cmd ls s3://mybucket2/

# 파일 다운로드
s3cmd get s3://mybucket2/test_s3cmd.txt downloaded_file.txt

# 파일 삭제
s3cmd rm s3://mybucket2/test_s3cmd.txt

# 버킷 삭제 (비어있어야 함)
s3cmd rb s3://mybucket2