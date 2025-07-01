# Ceph 클러스터 설치 가이드 (Podman 버전)

이 프로젝트는 Kubernetes 없이 Podman을 컨테이너 엔진으로 사용하여 Ceph 클러스터를 설치하는 Vagrant 환경입니다.

## 개요

- **목적**: 단순 Ceph 클러스터 생성
- **컨테이너 엔진**: Podman
- **오케스트레이션**: 없음 (Kubernetes 제거)
- **스토리지 타입**: CephFS, RBD, Object Storage (RGW)
- **추가 기능**: Proxmox 저장소 미러링

## 시스템 요구사항

- Vagrant
- VirtualBox
- 최소 8GB RAM (마스터: 4GB, 워커: 2GB × 2)
- 최소 20GB 디스크 공간

## 클러스터 구성

```
ceph-master (192.168.57.10) - 마스터 노드
├── ceph-worker-1 (192.168.57.11) - 워커 노드
└── ceph-worker-2 (192.168.57.12) - 워커 노드
```

## 설치 방법

### 1. 사전 준비

```bash
# OSD 디스크 디렉토리 생성
mkdir -p OSD

# password.rb 파일 생성 (비밀번호 설정)
echo 'VAGRANT_PASSWORD = "vagrant"' > password.rb
```

### 2. 클러스터 시작

```bash
# 클러스터 시작
vagrant up

# 또는 특정 노드만 시작
vagrant up ceph-master
vagrant up ceph-worker-1
vagrant up ceph-worker-2
```

### 3. 설치 과정

1. **Podman 설치**: 모든 노드에 Podman 설치
2. **Ceph 클러스터 부트스트랩**: 마스터 노드에서 Ceph 클러스터 초기화
3. **워커 노드 추가**: 워커 노드들을 클러스터에 추가
4. **OSD 배포**: 워커 노드의 디스크를 OSD로 사용
5. **스토리지 서비스 설치**: CephFS, RBD, Object Storage 설치
6. **Proxmox 미러링 설정**: CephFS에 Proxmox 저장소 미러링

## 접속 정보

### SSH 접속
```bash
# 마스터 노드
vagrant ssh ceph-master

# 워커 노드
vagrant ssh ceph-worker-1
vagrant ssh ceph-worker-2
```

### Ceph Dashboard
- URL: http://192.168.57.10:8080
- 사용자: admin
- 비밀번호: admin

### Object Storage (RGW)
- S3 Endpoint: http://192.168.57.10:7480
- Swift Endpoint: http://192.168.57.10:7480/auth/v1.0

### Proxmox 미러링 웹 서버
- URL: http://192.168.57.10:8081
- 미러링 경로: /mnt/cephfs/proxmox-mirror

## 사용법

### CephFS 사용
```bash
# 마운트
ceph-fuse /mnt/cephfs

# 해제
fusermount -u /mnt/cephfs

# 상태 확인
ceph fs status mycephfs
```

### RBD 사용
```bash
# 이미지 생성
rbd create --pool rbd-pool --image test-image --size 1G

# 디바이스 매핑
rbd map --pool rbd-pool --image test-image

# 마운트
mount /dev/rbd0 /mnt/rbd

# 언매핑
rbd unmap /dev/rbd0
```

### Object Storage 사용
```bash
# S3 API (s3cmd)
s3cmd ls
s3cmd put file.txt s3://bucket/
s3cmd get s3://bucket/file.txt

# Swift API
swift list
swift upload container file.txt
swift download container file.txt
```

### Proxmox 미러링 관리
```bash
# 관리 스크립트 실행
/usr/local/bin/proxmox-mirror-manage.sh [옵션]

# 옵션:
#   status    - 상태 확인
#   sync      - 수동 미러링 실행
#   restart   - nginx 재시작
#   logs      - 로그 실시간 확인
#   cron      - cronjob 상태 확인
#   disk      - 디스크 사용량 확인
#   test      - 웹 접속 테스트
#   backup    - 설정 백업
#   help      - 도움말 표시

# 예시:
/usr/local/bin/proxmox-mirror-manage.sh status
/usr/local/bin/proxmox-mirror-manage.sh sync
/usr/local/bin/proxmox-mirror-manage.sh logs
```

## 모니터링

### 클러스터 상태 확인
```bash
# 전체 상태
ceph -s

# 헬스 상세
ceph health detail

# OSD 상태
ceph osd status

# 풀 상태
ceph df

# 서비스 상태
ceph orch ls
```

### Prometheus 메트릭
- URL: http://192.168.57.10:9283/metrics

## 문제 해결

### 클러스터가 HEALTH_WARN 상태인 경우
```bash
# 상세 정보 확인
ceph health detail

# OSD 상태 확인
ceph osd status

# 풀 상태 확인
ceph df
```

### 서비스가 시작되지 않는 경우
```bash
# 서비스 상태 확인
ceph orch ls

# 서비스 로그 확인
ceph orch ps

# 서비스 재시작
ceph orch restart <service-name>
```

### Proxmox 미러링 문제 해결
```bash
# 상태 확인
/usr/local/bin/proxmox-mirror-manage.sh status

# nginx 재시작
/usr/local/bin/proxmox-mirror-manage.sh restart

# 로그 확인
/usr/local/bin/proxmox-mirror-manage.sh logs

# 수동 미러링 실행
/usr/local/bin/proxmox-mirror-manage.sh sync
```

## 정리

### 클러스터 중지
```bash
vagrant halt
```

### 클러스터 삭제
```bash
vagrant destroy -f
```

### OSD 디스크 정리
```bash
rm -rf OSD/
```

## Proxmox 미러링 상세 정보

### 미러링된 저장소
- **원본 URL**: [http://download.proxmox.com/debian/](http://download.proxmox.com/debian/)
- **로컬 경로**: `/mnt/cephfs/proxmox-mirror`
- **웹 접속**: http://192.168.57.10:8081

### 포함된 저장소
- ceph-luminous, ceph-nautilus, ceph-octopus, ceph-pacific, ceph-quincy, ceph-reef, ceph-squid
- corosync-3, devel, dists, pbs, pbs-client, pdm, pmg, pve
- GPG 키 파일들

### 자동화 설정
- **미러링 스케줄**: 매일 새벽 2시
- **로그 로테이션**: 매주 일요일 새벽 3시 (7일 이상 된 로그 삭제)
- **nginx 캐싱**: .deb, .gpg, .asc 파일에 대해 1일 캐시

### 성능 최적화
- gzip 압축 활성화
- 적절한 캐시 헤더 설정
- 디렉토리 인덱싱 활성화
- 보안 헤더 추가

## 주의사항

1. 이 환경은 테스트/개발용입니다. 프로덕션 환경에서는 보안 설정을 강화하세요.
2. OSD 디스크는 VirtualBox VDI 파일로 생성됩니다. 실제 환경에서는 물리 디스크를 사용하세요.
3. 기본 복제 계수는 2로 설정되어 있습니다. 3개 이상의 노드가 권장됩니다.
4. Proxmox 미러링은 초기에 시간이 오래 걸릴 수 있습니다.
5. 충분한 디스크 공간을 확보하세요 (미러링을 위해 추가 공간 필요).

## 추가 정보

- [Ceph 공식 문서](https://docs.ceph.com/)
- [Cephadm 가이드](https://docs.ceph.com/en/latest/cephadm/)
- [Podman 문서](https://podman.io/getting-started/)
- [Proxmox 저장소](http://download.proxmox.com/debian/) 