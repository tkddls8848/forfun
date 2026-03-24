# IBM Storage Scale — NSD 서버와 IBM Cloud FS 스토리지 연결 방안

## 개요

이 문서는 AWS에 배포된 NSD 서버(`nsd-1`, `nsd-2`)와 IBM의 GPFS 기반 스토리지를
IBM Cloud 또는 IBM TechZone을 통해 연결하는 방법을 정리합니다.

---

## 연결 아키텍처 선택지

### 옵션 A: IBM Storage Scale on AWS (권장 — 비용 발생)

IBM Marketplace에서 제공하는 **IBM Storage Scale BYOL AMI**를 사용해
AWS 내에서 완전한 GPFS 클러스터를 구성하는 방식입니다.

```
[AWS k8s-storage-lab VPC]
  nsd-1 / nsd-2  ──── GPFS daemon port (1191/TCP) ────  Scale 노드 (AWS)
```

- **장점**: 네트워크 지연 없음 (동일 리전 내 VPC peering 또는 동일 VPC)
- **단점**: AMI 라이선스 비용 발생 (BYOL 또는 시간당 과금)
- **참고**: AWS Marketplace에서 "IBM Storage Scale" 검색

---

### 옵션 B: IBM TechZone — 파트너 무료 환경

IBM 파트너 계정으로 **IBM Technology Zone (TechZone)** 에서
Storage Scale 실습 환경을 무료로 요청할 수 있습니다.

#### TechZone 환경 요청 절차

1. [https://techzone.ibm.com](https://techzone.ibm.com) 접속 → IBM ID 로그인
2. `Storage Scale` 검색 → **"IBM Storage Scale — Evaluation"** 또는
   **"IBM Spectrum Scale — Hands-on Lab"** 선택
3. 환경 요청 (Reservation) 생성
   - Duration: 최대 4일 (연장 가능)
   - Region: `us-east` 또는 `eu-de` 선택
4. 승인 후 접속 정보 (공인 IP, SSH 키) 이메일 수신

#### TechZone 환경 연결 제약

| 항목 | 내용 |
|------|------|
| 접근 방식 | SSH 터널 또는 VPN (OpenVPN) 제공 |
| 네트워크 | TechZone ↔ AWS 직접 peering 불가, 인터넷 경유 |
| GPFS 포트 | 1191/TCP (daemon), 1191/UDP — 방화벽 개방 필요 |
| 지연시간 | 인터넷 경유이므로 고지연 → 프로덕션 부적합, 실습 용도 적합 |

---

### 옵션 C: IBM Cloud — File Storage for VPC (관리형)

IBM Cloud의 관리형 파일 스토리지 서비스를 NFS로 마운트하는 방식입니다.
GPFS 프로토콜을 직접 사용하지 않고, NFS 엔드포인트를 통해 접근합니다.

```
[AWS nsd-1/nsd-2]
  │
  └── (인터넷 또는 Direct Link) ──→  IBM Cloud File Storage for VPC
                                      (NFS v4.1 엔드포인트)
```

- **장점**: 완전 관리형, GPFS 설치 불필요
- **단점**: AWS ↔ IBM Cloud 직접 전용선(Direct Link) 없으면 인터넷 경유
- **용도**: NSD 서버 자체는 사용하지 않음 — NFS 클라이언트로만 동작

---

### 옵션 D: IBM Storage Scale on IBM Cloud VPC (권장 — GPFS 직접 사용)

IBM Cloud VPC에 Scale 클러스터를 구성하고,
AWS NSD 서버와 **IBM Cloud Direct Link** 또는 **Megaport** 를 통해 연결합니다.

```
[AWS VPC]                            [IBM Cloud VPC]
  nsd-1 ──── Direct Link / Megaport ──→  Scale Manager Node
  nsd-2                                   Scale NSD Node × 2
  (GPFS client)                           (GPFS 파일시스템 제공)
```

#### IBM Cloud Scale 클러스터 구성 방법

```bash
# IBM Cloud CLI 설치 후
ibmcloud login
ibmcloud plugin install vpc-infrastructure

# Storage Scale 배포 (Terraform 기반 자동화)
git clone https://github.com/IBM/ibm-spectrum-scale-cloud-install
cd ibm-spectrum-scale-cloud-install/ibmcloud_scale_templates/
# terraform.tfvars 설정 후
terraform init && terraform apply
```

- IBM 공식 Terraform 템플릿: [github.com/IBM/ibm-spectrum-scale-cloud-install](https://github.com/IBM/ibm-spectrum-scale-cloud-install)

#### AWS NSD → IBM Cloud Scale 연결 (GPFS remote mount)

```bash
# AWS nsd-1에서 (GPFS 클라이언트로 동작)
sudo /usr/lpp/mmfs/bin/mmauth genkey new
sudo /usr/lpp/mmfs/bin/mmremotecluster add <ibmcloud-scale-cluster-name> \
  -n <ibmcloud-scale-node-ip> \
  -k /var/mmfs/ssl/id_rsa_scale.pub

sudo /usr/lpp/mmfs/bin/mmremotefs add <remote-fs-name> \
  -f <ibmcloud-fs-name> \
  -C <ibmcloud-scale-cluster-name> \
  -T /mnt/gpfs-remote

sudo /usr/lpp/mmfs/bin/mmmount <remote-fs-name>
```

---

## 권장 접근 방법 (실습 목적)

| 목적 | 권장 방안 |
|------|-----------|
| 빠른 기능 검증 (무료) | **옵션 B — TechZone** (4일 환경, SSH 터널) |
| AWS 내 완전한 구성 | **옵션 A — AWS Marketplace AMI** |
| IBM Cloud 연동 실습 | **옵션 D — IBM Cloud VPC + Direct Link** |
| GPFS 없이 공유 스토리지 | **옵션 C — IBM Cloud File Storage (NFS)** |

---

## TechZone 연결 시 NSD 서버 설정 요약

TechZone 환경이 준비된 경우 AWS NSD 서버에서 아래 포트를 열어야 합니다.

### Security Group 추가 규칙 (nsd SG)

| 프로토콜 | 포트 | 방향 | 출처 |
|----------|------|------|------|
| TCP | 1191 | Inbound | TechZone 공인 IP |
| UDP | 1191 | Inbound | TechZone 공인 IP |
| TCP | 1191 | Outbound | TechZone 공인 IP |

### OpenTofu로 규칙 추가 예시

```hcl
# opentofu/modules/security_group/main.tf 에 추가
resource "aws_security_group_rule" "nsd_gpfs_techzone_in" {
  type              = "ingress"
  from_port         = 1191
  to_port           = 1191
  protocol          = "tcp"
  cidr_blocks       = ["<techzone-public-ip>/32"]
  security_group_id = aws_security_group.nsd.id
}
```

---

## 참고 자료

- IBM TechZone: https://techzone.ibm.com
- IBM Storage Scale 문서: https://www.ibm.com/docs/en/storage-scale
- IBM Cloud Terraform 템플릿: https://github.com/IBM/ibm-spectrum-scale-cloud-install
- IBM Cloud Direct Link: https://www.ibm.com/cloud/direct-link
