# k3s-storage-lab

k3s(프론트) + cephadm/BeeGFS(백엔드) 분리 구성 기능검증 환경.
EC2 2대, ~$20/월 (주 5일 × 5시간 기준).

## 아키텍처

```
EC2 #1 t3.large — Frontend          EC2 #2 t3.medium — Backend
┌────────────────────────┐          ┌────────────────────────┐
│ k3s server (master)    │          │ cephadm                │
│ k3s agent-1 (worker-1) │◀────────▶│  MON/OSD/MGR/MDS       │
│ k3s agent-2 (worker-2) │          │                        │
│                        │          │ BeeGFS 7.4.6           │
│ Ceph CSI (RBD+CephFS)  │          │  mgmtd/meta/storaged   │
│ BeeGFS CSI             │          │                        │
└────────────────────────┘          └────────────────────────┘
```

## 사전 요구사항

- AWS CLI 설정 완료 (`aws configure`)
- OpenTofu 설치
- EC2 Key Pair (`storage-lab`) 및 PEM 파일 (`~/.ssh/storage-lab.pem`)

## 빠른 시작

```bash
# 1. tfvars 수정 (key_name 확인)
vi opentofu/terraform.tfvars

# 2. 전체 자동 구성 (약 15~20분)
bash start.sh

# 3. 검증
ssh -i ~/.ssh/storage-lab.pem ubuntu@<FRONTEND_IP>
bash scripts/05_verify.sh
```

## 단계별 실행

```bash
# Phase 1: 인프라
cd opentofu && tofu init && tofu apply

# Phase 2: k3s (EC2 #1에서)
ssh ubuntu@<FRONTEND_IP> 'bash -s' < scripts/01_k3s_frontend.sh

# Phase 3: Ceph (EC2 #2에서)
ssh ubuntu@<BACKEND_IP> 'bash -s' < scripts/02_ceph_backend.sh

# Phase 4: BeeGFS (EC2 #2에서)
ssh ubuntu@<BACKEND_IP> 'bash -s' < scripts/03_beegfs_backend.sh

# Phase 5: CSI (EC2 #1에서)
export BACKEND_PRIVATE_IP=<EC2#2 Private IP>
export CEPH_FSID=<ceph fsid>
export CEPH_ADMIN_KEY=<ceph auth get-key client.admin>
bash scripts/04_csi_install.sh

# Phase 6: 검증
bash scripts/05_verify.sh
```

## 삭제

```bash
bash destroy.sh
```

## 버전

| 항목 | 버전 |
|---|---|
| Ubuntu | 24.04 LTS |
| Kernel | 6.8 GA (고정) |
| k3s | v1.31.x+k3s1 |
| Ceph | Squid v19.2.x |
| BeeGFS | 7.4.6 |
| Ceph CSI | v3.12.x |
