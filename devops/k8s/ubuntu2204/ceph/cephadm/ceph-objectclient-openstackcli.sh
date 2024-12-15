#!/usr/bin/bash


# disable firewall
sudo ufw disable

# create object gateway server
### Keystone 설치
### Keystone 및 관련 패키지 설치
sudo apt-get upgrade -y


###openstack cli 설치
sudo apt-get install python3-pip -y
pip3 install python-openstackclient

###openstack cli 인식
echo 'export PATH=$PATH:~/.local/bin' >> ~/.bashrc
source ~/.bashrc

###**환경 설정 스크립트 /`openrc.sh` 생성**:
인증 스크립트를 작성하여 OpenStack CLI 도구를 사용할 수 있도록 설정합니다.

cat > ~/openstack-openrc.sh <<EOF
export OS_AUTH_URL=http://ceph1:5000/v3
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$KEYSTONE_BOOTSTRAP_PASSWORD ## keystone-manage bootstrap password
export OS_REGION_NAME=RegionOne ## keystone-manage bootstrap region-id
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_DOMAIN_NAME=default
export OS_IDENTITY_API_VERSION=3
EOF

파일을 실행하여 환경 설정을 적용합니다:

source ~/openstack-openrc.sh


openstack project create --domain default --description "My New openstackProject" $OPENSTACK_PROJECT
openstack user create --domain default --password $OPENSTACK_PASSWORD --email $OPENSTACK_EMAIL --project $OPENSTACK_PROJECT $OPENSTACK_USER
openstack role add --project $OPENSTACK_PROJECT --user $OPENSTACK_USER admin

# create object gateway server
sudo ceph orch apply rgw test

sudo radosgw-admin realm create --rgw-realm=testrealm --default
sudo radosgw-admin zonegroup create --rgw-zonegroup=testzonegroup --rgw-realm=testrealm --endpoints=http://ceph1:8080
sudo radosgw-admin zone create --rgw-zone=testzone --rgw-zonegroup=testzonegroup --master --endpoints=http://ceph1:8080

sudo ceph orch apply rgw testrealm testzonegroup --placement=ceph1

3. **RGW 설정 파일 수정**

RGW_INSTANCE_NAME=$(sudo ceph orch ps --daemon_type rgw | awk '{print $1}'| tail -n 1)
rgw.test.ceph1.ecayxu

RGW 서비스를 위해 `ceph.conf` 또는 별도의 RGW 설정 파일에 Swift API를 활성화하도록 설정합니다. 주로 `/etc/ceph/ceph.conf`에 다음과 같은 내용을 추가합니다:

```ini
[client.rgw.$RGW_INSTANCE_NAME]
rgw frontends = "civetweb port=7480"
rgw swift account in url = true
rgw enable swift = true
```

4. **RGW 서비스 시작**

설정을 완료한 후, RGW 서비스를 시작합니다. 대부분의 경우, 다음과 같은 명령으로 RGW 데몬을 시작할 수 있습니다:

```bash
sudo ceph orch restart rgw.test
```

또는 cephadm을 사용하는 경우, 해당 서비스 이름을 사용하여 시작할 수 있습니다.

5. **OpenStack Swift와의 연동 확인**

RGW가 Swift API 지원을 위해 설정되었는지 테스트합니다. Swift API 클라이언트(예: `swift` CLI)를 사용하여 RGW에 요청을 보내고 응답을 확인하십시오.
# disable firewall
sudo ufw disable
#sudo apt-get install python3-openstackclient -y
sudo apt-get install python3-swiftclient -y
swift -A http://ceph1:7480/auth -U $OPENSTACK_PROJECT:$OPENSTACK_USER -K $OPENSTACK_PASSWORD list



sudo useradd -s /bin/bash -d /opt/stack -m stack

sudo chmod +x /opt/stack

echo "stack ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/stack

sudo su stack 

sudo apt-get install git -y
cd ~
git clone https://opendev.org/openstack/devstack
cd ~/devstack

cat > ./local.conf <<EOF

[[local|localrc]]
# 주 관리자 비밀번호 설정
ADMIN_PASSWORD=password
DATABASE_PASSWORD=password
RABBIT_PASSWORD=password
SERVICE_PASSWORD=password

# 비활성화할 모든 서비스
disable_all_services

# 활성화할 서비스
enable_service key  # Keystone
enable_service swift  # Swift 초기화 서비스
enable_service s-proxy  # Swift 프록시
enable_service s-object  # Swift 객체
enable_service s-container  # Swift 컨테이너
enable_service s-account  # Swift 계정

# SWIFT 해시 설정
SWIFT_HASH=$(echo -n "random-string-$(date +%s%N)" | sha256sum | awk '{print $1}')

# Host IP 설정
HOST_IP=$(hostname -I | awk '{print $2}')  # 실제 IP로 변경

# 로그 설정
LOGFILE=$HOME/devstack.log

# 필요에 따라 추가적인 서비스 활성화
# enable_service n-net
# enable_service cinder
EOF

./stack.sh




# install swift client
sudo apt install -y python3-swiftclient

# create object gateway server
sudo ceph orch apply rgw ceph1

sudo apt-get install python3-swiftclient -y
swift -A http://ceph1:7480/auth -U $OPENSTACK_PROJECT:$OPENSTACK_USER -K $OPENSTACK_PASSWORD list


# install swift client
sudo apt-get install python3-swiftclient -y 

# create object gateway server
sudo ceph orch apply rgw ceph1
sudo radosgw-admin user create --uid="swiftuser" --display-name="Swift User" --caps="buckets=*; users=*" > userinfo.txt

mkdir -p ~/.swift
cat > ~/.swift/swift.conf << EOF
[swift]
auth_version = 1
auth_url = http://$(hostname):7480/auth/v1.0
username = swiftuser
password = swiftuserpassword
EOF










































# install keystone
sudo apt-get install keystone apache2 libapache2-mod-wsgi-py3 -y

### **데이터베이스 설정**:
###MariaDB 설치 및 설정**:
sudo apt-get install mariadb-server python3-pymysql -y

cat > ~/config.conf <<EOF
export KEYSTONE_GROUP="keystone"
export KEYSTONE_USER="keystone"
export KEYSTONE_DATABASE_PASSWORD="keystonepassword"
export KEYSTONE_BOOTSTRAP_PASSWORD="ADMINPASS"

export OS_PROJECT="openstackproject"
export OS_USER="openstackuser"
export OS_PASSWORD="openstackpassword"
export OS_EMAIL="tkddls8848@naver.com"
EOF
export KEYSTONE_GROUP="keystone"
export KEYSTONE_USER="keystone"
export KEYSTONE_DATABASE_PASSWORD="keystonepassword"
export KEYSTONE_BOOTSTRAP_PASSWORD="ADMINPASS"
export OS_PROJECT_NAME='admin'
export OS_USERNAME='admin'
## keystone-manage bootstrap password
export OS_PASSWORD=$KEYSTONE_BOOTSTRAP_PASSWORD 
## keystone-manage bootstrap region-id
export OS_REGION_NAME='RegionOne' 
export OS_USER_DOMAIN_NAME='default'
export OS_PROJECT_DOMAIN_NAME='default'
export OS_IDENTITY_API_VERSION=3
export OS_AUTH_VERSION=3
export OS_AUTH_URL='http://ceph1:5000/v3'

source ~/config.conf

###데이터베이스 보안 설정**:
sudo apt-get install expect -y
cat << EOF >> mysql_secure_installation.sh
#!/usr/bin/expect -f
spawn sudo mysql_secure_installation
expect {
    "Enter current password for root" {
        send "\r"; exp_continue
    }
    "Switch to unix_socket authentication" {
        send "n\r"; exp_continue
    }
    "Change the root password?" {
        send "n\r"; exp_continue
    }
    "Remove anonymous users?" {
        send "Y\r"; exp_continue
    }
    "Disallow root login remotely?" {
        send "Y\r"; exp_continue
    }
    "Remove test database and access to it?" {
        send "Y\r"; exp_continue
    }
    "Reload privilege tables now?" {
        send "Y\r"; exp_continue
    }
}
EOF
sudo chmod +x mysql_secure_installation.sh
./mysql_secure_installation.sh
sudo rm mysql_secure_installation.sh

###Keystone 데이터베이스와 사용자 생성**:
cat << EOF >> query.sql
CREATE DATABASE keystone;
CREATE USER 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DATABASE_PASSWORD';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DATABASE_PASSWORD';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DATABASE_PASSWORD';
FLUSH PRIVILEGES;
EOF

cat << EOF >> mysql.sh
sudo mysql -u root < query.sql
EOF
sudo chmod +x mysql.sh
./mysql.sh
sudo rm mysql.sh

###Keystone 설정 파일 편집**:

## #로 시작하는 주석제거
sudo sed -i.bak '/^\s*#/d' "/etc/keystone/keystone.conf" 
## [database] 수정
sudo sed -i.bak "s,sqlite:////var/lib/keystone/keystone.db,mysql+pymysql://keystone:$KEYSTONE_DATABASE_PASSWORD@localhost/keystone,g" "/etc/keystone/keystone.conf"
## [token] 프로바이더 fernet 추가
sudo sed -i.bak '/\[token\]/a provider=fernet' "/etc/keystone/keystone.conf"

###**Keystone 데이터베이스 초기화**:
sudo su -s /bin/bash keystone -c "keystone-manage db_sync"

###**Fernet 키 저장소 초기화**:
sudo keystone-manage fernet_setup --keystone-user $KEYSTONE_USER --keystone-group $KEYSTONE_GROUP
sudo keystone-manage credential_setup --keystone-user $KEYSTONE_USER --keystone-group $KEYSTONE_GROUP

###**Bootstrap 명령 실행**:
외부에서 Keystone에 접근하기 위한 기본 정보를 설정합니다.

sudo keystone-manage bootstrap --bootstrap-password $KEYSTONE_BOOTSTRAP_PASSWORD \
    --bootstrap-admin-url http://ceph2:5000/v3/ \
    --bootstrap-internal-url http://ceph2:5000/v3/ \
    --bootstrap-public-url http://ceph2:5000/v3/ \
    --bootstrap-region-id RegionOne

###**Apache 서버 구성**:
- Apache를 설정하여 Keystone이 서비스되도록 합니다.
sudo echo "ServerName ceph1" | sudo tee -a /etc/apache2/apache2.conf
sudo service apache2 restart
###RGW 포트 번호 변경(키스톤 아파치 서버와 충돌 피하기 위해 및 기타 설정**:
# create object gateway server
sudo ceph orch apply rgw ceph1



sudo bash -c 'cat >> /etc/ceph/ceph.conf << EOF 
[client.rgw.gateway]
#   rgw_frontends = civetweb port=8080
    rgw_keystone_url = http://ceph2:5000/
    rgw_keystone_version = 3
    rgw_keystone_auth_url = http://ceph2:5000/v3
    rgw_keystone_admin_user = adminuser
    rgw_keystone_admin_password = adminpassword
    rgw_keystone_admin_tenant = admintenant
    rgw_keystone_admin_domain = admindomain
    auth_service = keystone
EOF'

# install swift client
sudo apt-get install python3-swiftclient -y 
sudo apt-get install python3-openstackclient -y

export OS_PROJECT_NAME='admin'
export OS_USERNAME='admin'
export OS_PASSWORD=$KEYSTONE_BOOTSTRAP_PASSWORD ## keystone-manage bootstrap password
export OS_REGION_NAME='RegionOne' ## keystone-manage bootstrap region-id
export OS_USER_DOMAIN_NAME='default'
export OS_PROJECT_DOMAIN_NAME='default'
export OS_IDENTITY_API_VERSION=3
export OS_AUTH_VERSION=3
export OS_AUTH_URL='http://ceph1:5000/v3'




   - **컨테이너 생성**:
  ```bash
  swift post test
  ```

- **객체 업로드**:
  ```bash
  swift upload <container-name> <file-name>
  ```

- **객체 다운로드**:
  ```bash
  swift download <container-name> <file-name>
  ```

- **컨테이너 목록 조회**:
  ```bash


swift -A http://ceph1:7480/auth/v1.0 -U swiftuser -K swiftuserpassword list
  ```


