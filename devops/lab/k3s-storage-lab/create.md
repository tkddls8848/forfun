# k3s-storage-lab 구성 계획

## 개요

기존 kubeadm 기반 HCI 구성을 경량화하여  
EC2 2대로 k3s(프론트) + cephadm/BeeGFS(백엔드)를 분리 구성하는 기능검증 환경.

---

## 아키텍처
```
EC2 #1 - Frontend (k3s)              EC2 #2 - Backend (Storage)
┌────────────────────────────┐       ┌────────────────────────────┐
│ k3s server  (master)       │       │ cephadm                    │
│ k3s agent-1 (worker-1)    │       │  └ MON × 1                 │
│ k3s agent-2 (worker-2)    │◀─────▶│  └ OSD × 1 (5GB /dev/xvdb) │
│                            │       │  └ MGR × 1                 │
│ Ceph CSI Controller        │       │  └ MDS × 1 (CephFS용)      │
│ Ceph CSI Node (DaemonSet)  │       │                            │
│ BeeGFS CSI Controller      │       │ BeeGFS                     │
│ BeeGFS CSI Node (DaemonSet)│       │  └ mgmtd (port 8008)       │
└────────────────────────────┘       │  └ meta  (port 8005)       │
                                     │  └ storaged (5GB /dev/xvdc) │
                                     └────────────────────────────┘
```

---

## 버전 호환성 매트릭스

### OS / 커널

| 항목 | 버전 | 비고 |
|---|---|---|
| Ubuntu | 24.04 LTS (Noble) | AWS AMI 기본 GA 커널 사용 |
| Kernel | **6.8 GA 고정** | HWE 업그레이드 금지 |

> ⚠️ Ubuntu 24.04 GA 커널은 6.8이며 이를 고정 사용한다.  
> HWE 커널(6.11+)은 Ubuntu 24.04 기준 비공식 — BeeGFS 클라이언트 DKMS 빌드 실패 가능.  
> BeeGFS 7.4.6이 커널 6.11까지 지원한다고 명시하나, 이는 Ubuntu 24.10(GA 6.11) 기준이며  
> Ubuntu 24.04 HWE로 6.11을 올리는 것은 공식 지원 범위 밖이다.  
> 따라서 `apt-mark hold linux-image-*` 로 커널 고정 권장.

---

### k3s / Kubernetes

| 항목 | 버전 | 비고 |
|---|---|---|
| k3s | **v1.31.x+k3s1** | Ubuntu 24.04 공식 지원, CSI 호환 검증 |
| Kubernetes | 1.31 | 현 프로젝트 기준 버전 유지 |
| containerd | 2.0 (k3s 내장) | 별도 설치 불필요 |
| CNI | Flannel VXLAN (k3s 내장) | k3s 기본값 |

> k3s v1.32부터 containerd 2.0으로 변경되어 config 스키마가 바뀜.  
> 버전 일관성 및 안정성을 위해 **v1.31 계열** 사용.  
> k3s agent를 동일 EC2에서 2개 기동하여 worker-1, worker-2 역할 수행.

---

### Ceph (cephadm)

| 항목 | 버전 | 비고 |
|---|---|---|
| Ceph | **Squid v19.2.x** | Ubuntu 24.04 apt 기본 패키지 |
| cephadm | v19.2.x | `apt install cephadm` |
| 컨테이너 런타임 | Podman (cephadm 기본) | |
| 복제 설정 | size=1, min_size=1 | 단일 OSD — 기능검증 전용 |
| OSD 디스크 | 5GB gp3 (/dev/xvdb) | raw 디바이스 직접 사용 |
| Ceph CSI | **v3.12.x** | K8s 1.28~1.31 호환 |

> Ubuntu 24.04 apt 저장소에 Ceph Squid(v19) 포함.  
> 별도 Ceph 저장소 추가 불필요.  
> 단일 노드 구성 시 HEALTH_WARN 상태 정상 — 기능검증 목적으로 허용.

---

### BeeGFS

| 항목 | 버전 | 비고 |
|---|---|---|
| BeeGFS | **7.4.6** | Ubuntu 24.04 + 커널 6.8 공식 지원 (7.4.5부터) |
| APT 저장소 | `https://www.beegfs.io/release/beegfs_7.4.6/` | |
| 클라이언트 모듈 | DKMS (`beegfs-client-dkms`) | 커널 모듈 자동 빌드 |
| 스토리지 디스크 | 5GB gp3 (/dev/xvdc) | XFS 포맷 |
| CSI Driver | **beegfs.csi.netapp.com** | ThinkParQ 공식 |
| CSI 배포 방식 | **kustomize** (공식 기본) | Helm 미제공 |

> ✅ BeeGFS 7.4.5부터 Ubuntu 24.04(커널 6.8) 공식 지원 시작.  
> ⚠️ `beegfs-client`와 `beegfs-client-dkms`는 상호 배타적 — 하나만 설치.  
> ⚠️ `connDisableAuthentication = true` 전 데몬 필수 설정.  
> ⚠️ CSI Node Plugin은 hostNetwork 사용 — mgmtd 접근 시 DNS 불가, IP 직접 지정 필요.

---

## 인프라 구성

### EC2 스펙

| 항목 | EC2 #1 (Frontend) | EC2 #2 (Backend) |
|---|---|---|
| 역할 | k3s server + agent × 2 | cephadm + BeeGFS |
| 인스턴스 | t3.large (2vCPU / 8GB) | t3.medium (2vCPU / 4GB) |
| OS | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS |
| 서브넷 | Public | Public |
| Root EBS | 20GB gp3 | 20GB gp3 |
| 추가 EBS | 없음 | /dev/xvdb 5GB (OSD) + /dev/xvdc 5GB (BeeGFS) |

### 네트워크
```
Internet
    │
   IGW
    │
    ├── EC2 #1 (Public IP)
    │   SG: SSH(22), K8s API(6443), NodePort(30000-32767)
    │
    └── EC2 #2 (Public IP)
        SG: SSH(22),
            Ceph MON(6789/3300), Ceph MDS(6800-7300),
            BeeGFS mgmtd(8008), meta(8005), storaged(8003), helperd(8004)
```

- NAT GW 없음 — EC2 Public IP로 직접 인터넷 접근
- VPC 내부 EC2 간 통신: SG 상호 허용

---

## 구현 단계

### Phase 1. OpenTofu 인프라
```
├── VPC (10.0.0.0/16)
├── Public 서브넷 (10.0.0.0/24)
├── IGW + 라우팅 테이블
├── SG: frontend / backend
├── EC2 #1 t3.large  — frontend
├── EC2 #2 t3.medium — backend
└── EBS: /dev/xvdb 5GB + /dev/xvdc 5GB → EC2 #2 attach
```

### Phase 2. Frontend — k3s 구성
```
1. 사전 준비
   - swap off
   - 커널 고정: apt-mark hold linux-image-* linux-headers-*
   - 커널 모듈: overlay, br_netfilter 로드

2. k3s server 설치 (v1.31.x)
   - INSTALL_K3S_VERSION=v1.31.x+k3s1
   - --disable traefik (불필요 시)
   - --node-label role=master

3. k3s agent × 2 설치 (동일 EC2)
   - K3S_URL=https://<EC2#1 IP>:6443
   - K3S_TOKEN 환경변수로 join
   - --node-label role=worker
   - agent-1, agent-2 각각 별도 systemd unit

4. kubeconfig 설정
   - /etc/rancher/k3s/k3s.yaml → ~/.kube/config

5. 확인
   - kubectl get nodes (3노드: server + agent×2)
```

### Phase 3. Backend — Ceph 구성
```
1. 사전 준비
   - 커널 고정 (EC2 #1과 동일)
   - python3, podman 설치

2. cephadm 설치
   - apt install cephadm

3. 클러스터 부트스트랩
   - cephadm bootstrap --mon-ip <EC2#2 Private IP> \
       --single-host-defaults \
       --skip-monitoring-stack

4. 단일 노드 설정
   - ceph config set global osd_pool_default_size 1
   - ceph config set global osd_pool_default_min_size 1

5. OSD 추가
   - ceph orch daemon add osd <hostname>:/dev/xvdb

6. CephFS 활성화
   - ceph fs volume create cephfs

7. 확인
   - ceph -s (HEALTH_WARN 허용)
   - ceph osd tree

8. CSI 연동용 정보 수집
   - ceph fsid
   - ceph auth get-key client.admin
   - ceph mon dump (모니터 IP)
```

### Phase 4. Backend — BeeGFS 구성
```
1. APT 저장소 추가
   - wget -q https://www.beegfs.io/release/beegfs_7.4.6/gpg/GPG-KEY-beegfs -O- | apt-key add -
   - echo "deb https://www.beegfs.io/release/beegfs_7.4.6/dists/noble/ noble non-free" \
       > /etc/apt/sources.list.d/beegfs.list

2. 패키지 설치
   - beegfs-mgmtd
   - beegfs-meta
   - beegfs-storage
   - beegfs-client-dkms   ← beegfs-client와 상호 배타적
   - beegfs-helperd
   - beegfs-utils
   - linux-headers-$(uname -r)  ← DKMS 빌드 필수

3. 스토리지 디스크 준비
   - mkfs.xfs /dev/xvdc
   - mkdir -p /mnt/beegfs/storage
   - mount /dev/xvdc /mnt/beegfs/storage
   - echo "/dev/xvdc /mnt/beegfs/storage xfs defaults 0 0" >> /etc/fstab

4. mgmtd 초기화 및 설정
   - /opt/beegfs/sbin/beegfs-setup-mgmtd -p /mnt/beegfs/mgmtd
   - beegfs-mgmtd.conf: connDisableAuthentication = true

5. meta 초기화 및 설정
   - /opt/beegfs/sbin/beegfs-setup-meta -p /mnt/beegfs/meta \
       -s 1 -m <EC2#2 IP>
   - beegfs-meta.conf: connDisableAuthentication = true

6. storaged 초기화 및 설정
   - /opt/beegfs/sbin/beegfs-setup-storage -p /mnt/beegfs/storage \
       -s 1 -i 1 -m <EC2#2 IP>
   - beegfs-storage.conf: connDisableAuthentication = true

7. 데몬 기동
   - systemctl enable --now beegfs-mgmtd
   - systemctl enable --now beegfs-meta
   - systemctl enable --now beegfs-storage

8. 확인
   - beegfs-ctl --listnodes --nodetype=storage
   - beegfs-ctl --listnodes --nodetype=meta
```

### Phase 5. CSI 연동 (EC2 #1에서 실행)

#### 5-1. Ceph CSI
```
1. Namespace 생성
   - kubectl create namespace ceph-csi

2. ConfigMap 생성 (모니터 정보)
   - ceph-csi-config: fsid + mon IP 주소

3. Secret 생성 (인증 키)
   - csi-rbd-secret: admin key
   - csi-cephfs-secret: admin key

4. Ceph CSI Driver 설치 (Helm)
   - helm repo add ceph-csi https://ceph.github.io/csi-charts
   - helm install ceph-csi-rbd ceph-csi/ceph-csi-rbd -n ceph-csi
   - helm install ceph-csi-cephfs ceph-csi/ceph-csi-cephfs -n ceph-csi

5. StorageClass 생성
   - ceph-rbd  (RWO, Block)
   - ceph-cephfs (RWX, Filesystem)
```

#### 5-2. BeeGFS CSI (kustomize — 공식 기본 방식)
```
1. 소스 clone
   - git clone --depth 1 https://github.com/ThinkParQ/beegfs-csi-driver.git

2. csi-beegfs-config.yaml 수정 (overlay 커스터마이징)
   - 경로: deploy/k8s/overlays/default/csi-beegfs-config.yaml
   - 내용:
     config:
       beegfsClientConf:
         connDisableAuthentication: "true"
     fileSystemSpecificConfigs:
       - sysMgmtdHost: <EC2#2 IP>   ← DNS 불가, IP 직접 지정
         config:
           beegfsClientConf:
             connDisableAuthentication: "true"

3. kustomize 배포
   - kubectl apply -k beegfs-csi-driver/deploy/k8s/overlays/default

4. 배포 확인 대기
   - kubectl rollout status statefulset/csi-beegfs-controller -n beegfs-csi
   - kubectl rollout status daemonset/csi-beegfs-node -n beegfs-csi

5. StorageClass 생성
   - beegfs-scratch (RWX)
   - sysMgmtdHost: <EC2#2 IP>
   - volDirBasePath: /k8s/dynamic
```

### Phase 6. 검증
```
1. StorageClass 확인
   - kubectl get storageclass
   (ceph-rbd, ceph-cephfs, beegfs-scratch)

2. PVC 생성 테스트
   - ceph-rbd PVC    → RWO Pod 마운트 → 읽기/쓰기
   - ceph-cephfs PVC → RWX Pod 마운트 → 읽기/쓰기
   - beegfs-scratch PVC → RWX Pod 마운트 → 읽기/쓰기

3. 확인 명령
   - kubectl get pvc
   - kubectl get pods
   - kubectl exec <pod> -- df -h
   - kubectl exec <pod> -- dd if=/dev/zero of=/mnt/test bs=1M count=100
```

---

## 디렉토리 구조
```
k3s-storage-lab/
├── opentofu/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── vpc/
│       ├── security_group/
│       └── ec2/              # frontend + backend (EBS 포함)
├── scripts/
│   ├── 01_k3s_frontend.sh   # k3s server + agent 설치
│   ├── 02_ceph_backend.sh   # cephadm bootstrap + OSD + CephFS
│   ├── 03_beegfs_backend.sh # BeeGFS 설치 + 데몬 구성
│   ├── 04_csi_install.sh    # Ceph CSI(Helm) + BeeGFS CSI(kustomize)
│   └── 05_verify.sh         # PVC 생성 및 검증
├── manifests/
│   ├── ceph-csi/
│   │   ├── csi-config.yaml       # fsid + mon IP
│   │   ├── secret-rbd.yaml
│   │   ├── secret-cephfs.yaml
│   │   ├── storageclass-rbd.yaml
│   │   └── storageclass-cephfs.yaml
│   ├── beegfs-csi/
│   │   ├── kustomization.yaml          # overlay 진입점
│   │   ├── csi-beegfs-config.yaml      # mgmtd IP + connDisableAuthentication
│   │   └── storageclass-beegfs.yaml    # beegfs-scratch
│   └── test-pvc/
│       ├── test-rbd.yaml
│       ├── test-cephfs.yaml
│       └── test-beegfs.yaml
├── start.sh      # 전체 구성 자동화 (Phase 1~5 순차 실행)
├── destroy.sh    # 전체 삭제 (tofu destroy)
└── README.md
```

---

## 예상 비용 (주 5일 × 5시간 = 108hr/월, ap-northeast-2)

| 항목 | 단가 | 월비용 |
|---|---|---|
| EC2 #1 t3.large | $0.1040/hr | $11.23 |
| EC2 #2 t3.medium | $0.0416/hr | $4.49 |
| EBS root 20GB × 2 (gp3) | $0.0952/GB/월 | $3.81 |
| EBS 추가 10GB (gp3) | $0.0952/GB/월 | $0.95 |
| NAT GW | - | $0 |
| **합계** | | **~$20/월** |

> 기존 구성 대비 **약 83% 절감**

---

## 주의사항 및 제약

| 항목 | 내용 |
|---|---|
| 가용성 | 단일 MON/OSD — 기능검증 전용, 프로덕션 불가 |
| k3s HA | 없음 — server 단일 구성 |
| BeeGFS HA | 없음 — mgmtd/meta 단일 구성 |
| 커널 고정 | GA 커널 6.8 유지 — `apt-mark hold linux-image-* linux-headers-*` |
| Ceph 복제 | size=1 강제 — HEALTH_WARN 정상 허용 |
| BeeGFS 인증 | `connDisableAuthentication = true` 전 데몬 필수 |
| BeeGFS CSI IP | CSI Node Plugin hostNetwork 사용 — mgmtd는 DNS 불가, IP 직접 지정 |
| BeeGFS CSI 배포 | kustomize 공식 방식 — Helm 미제공 |
| EC2 재시작 | Public IP 변경 — EIP 적용 또는 재시작 후 IP 갱신 필요 |