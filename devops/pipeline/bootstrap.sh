#!/bin/bash

echo "=== Kafka 개발 환경 설정 시작 ==="

# 시스템 업데이트
apt-get update
apt-get upgrade -y

# Java 11 설치
echo "Java 11 설치 중..."
apt-get install -y openjdk-11-jdk

# JAVA_HOME 설정
echo 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64' >> /home/vagrant/.bashrc
echo 'export PATH=$PATH:$JAVA_HOME/bin' >> /home/vagrant/.bashrc

# Kafka 사용자 생성
useradd -m -s /bin/bash kafka

# Kafka 다운로드 및 설치
echo "Kafka 다운로드 및 설치 중..."
cd /opt
wget https://downloads.apache.org/kafka/3.7.2/kafka_2.13-3.7.2.tgz
tar -xzf kafka_2.13-3.7.2.tgz
mv kafka_2.13-3.7.2 kafka
chown -R kafka:kafka /opt/kafka

# Kafka 환경변수 설정
echo 'export KAFKA_HOME=/opt/kafka' >> /home/vagrant/.bashrc
echo 'export PATH=$PATH:$KAFKA_HOME/bin' >> /home/vagrant/.bashrc

# ZooKeeper 설정 파일 수정
cat > /opt/kafka/config/zookeeper.properties << EOF
dataDir=/opt/kafka/zookeeper-data
clientPort=2181
maxClientCnxns=0
admin.enableServer=false
EOF

# Kafka 서버 설정 파일 수정
cat > /opt/kafka/config/server.properties << EOF
broker.id=0
listeners=PLAINTEXT://0.0.0.0:9092
advertised.listeners=PLAINTEXT://192.168.56.10:9092
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.dirs=/opt/kafka/kafka-logs
num.partitions=1
num.recovery.threads.per.data.dir=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
zookeeper.connect=localhost:2181
zookeeper.connection.timeout.ms=18000
group.initial.rebalance.delay.ms=0
EOF

# 데이터 디렉토리 생성
mkdir -p /opt/kafka/zookeeper-data
mkdir -p /opt/kafka/kafka-logs
chown -R kafka:kafka /opt/kafka

# systemd 서비스 파일 생성 (ZooKeeper)
cat > /etc/systemd/system/zookeeper.service << EOF
[Unit]
Description=Apache Zookeeper server
Documentation=http://zookeeper.apache.org
Requires=network.target remote-fs.target
After=network.target remote-fs.target

[Service]
Type=forking
User=kafka
Group=kafka
Environment=JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ExecStart=/opt/kafka/bin/zookeeper-server-start.sh -daemon /opt/kafka/config/zookeeper.properties
ExecStop=/opt/kafka/bin/zookeeper-server-stop.sh
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF

# systemd 서비스 파일 생성 (Kafka)
cat > /etc/systemd/system/kafka.service << EOF
[Unit]
Description=Apache Kafka Server
Documentation=http://kafka.apache.org/documentation.html
Requires=zookeeper.service
After=zookeeper.service

[Service]
Type=forking
User=kafka
Group=kafka
Environment=JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ExecStart=/opt/kafka/bin/kafka-server-start.sh -daemon /opt/kafka/config/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF

# systemd 재로드 및 서비스 활성화
systemctl daemon-reload
systemctl enable zookeeper
systemctl enable kafka

# 서비스 시작
systemctl start zookeeper
sleep 10
systemctl start kafka

# 방화벽 설정 (필요한 경우)
ufw allow 9092
ufw allow 2181

echo "=== Kafka 설정 완료 ==="
echo "ZooKeeper: localhost:2181"
echo "Kafka: localhost:9092"
echo "외부 접속: 192.168.56.10:9092"