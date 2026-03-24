# 03. 단계별 실행 가이드

## 사전 요구사항

| 항목 | 조건 |
|------|------|
| AWS CLI | v2, 자격증명 설정 완료 |
| OpenTofu | v1.6+ |
| jq | 설치 필요 |
| kubectl | 설치 필요 |
| helm | v3+ |
| SSH Key Pair | AWS에 등록, `~/.ssh/storage-lab.pem` 배치 |

> Windows 사용자: **WSL2**에서 실행. PEM 키를 WSL 홈으로 복사 후 `chmod 400`.

---

## 실행 흐름 요약

```
terraform.tfvars 수정
       ↓
bash start_k8s.sh          ← 인프라 + K8s (약 15~20분)
       ↓
bash start_ceph.sh         ← rook-ceph (약 15~20분)
       ↓
(선택) GPFS 수동 설치
       ↓
bash scripts/99_test_pvc.sh
```

---

## Step 0: 사전 준비

```bash
# 1. Key Pair 확인
ls ~/.ssh/storage-lab.pem
chmod 400 ~/.ssh/storage-lab.pem

# 2. terraform.tfvars 수정
vi opentofu/terraform.tfvars
# key_name     = "storage-lab"
# worker_count = 3
```

---

## Step 1: 인프라 + K8s 구성

```bash
bash start_k8s.sh
```

내부 실행 순서:
1. `[0/5]` 사전 요구사항 확인 (tofu, jq, ssh, aws, kubectl, helm)
2. `[1/5]` `tofu init` + `tofu apply` → EC2 6대 + EBS 8개 생성
3. `[2/5]` 60초 대기 후 `00_hosts_setup.sh` → IP 수집, /etc/hosts, SSH 키 배포
4. `[3/5]` `01_k8s_install.sh` → K8s 1.31 설치, kubeadm init, worker join, Flannel

완료 후 확인:
```bash
export KUBECONFIG=~/.kube/config-k8s-storage-lab
kubectl get nodes -o wide
# 모든 노드 Ready 상태 확인
```

---

## Step 2: rook-ceph 구성

```bash
bash start_ceph.sh
```

내부 실행 순서:
1. Helm 설치 (master-1)
2. rook-ceph operator 배포
3. CephCluster CR 생성 (worker 순차 OSD 초기화)
4. HEALTH_OK 확인
5. StorageClass 생성 (ceph-rbd, ceph-cephfs)

완료 후 확인:
```bash
export KUBECONFIG=~/.kube/config-k8s-storage-lab
kubectl -n rook-ceph get pods -o wide
kubectl get storageclass
# ceph-rbd, ceph-cephfs 확인
```

---

## Step 3: GPFS 설치 (수동, IBM 패키지 필요)

```bash
# 1. IBM Developer Edition .deb 패키지를 gpfs-packages/ 에 배치
ls gpfs-packages/

# 2. NSD 서버에 패키지 설치
bash scripts/04_gpfs_install.sh

# 3. GPFS 클러스터 구성
bash scripts/05_nsd_setup.sh

# 4. IBM Spectrum Scale CSI 설치
bash scripts/06_csi_gpfs.sh
```

---

## Step 4: 통합 테스트

```bash
bash scripts/99_test_pvc.sh
```

3개 StorageClass(ceph-rbd, ceph-cephfs, gpfs-scale) 각각 PVC + Pod를 생성해
동적 프로비저닝 및 마운트/I/O를 검증합니다.

성공 기준: 모든 PVC `Bound`, Pod 로그에 `OK` 출력.

---

## 재설치 및 삭제

```bash
# rook-ceph만 재설치
bash destroy_ceph.sh && bash start_ceph.sh

# 전체 삭제
bash destroy.sh
```

---

## 예상 비용 (ap-northeast-2, 실행 중 기준)

| 리소스 | 수량 | 시간당 |
|--------|------|--------|
| m5.large (master × 1) | 1 | ~$0.096 |
| m5.large (worker × 3) | 3 | ~$0.288 |
| t3.medium (nsd × 2) | 2 | ~$0.104 |
| EBS gp3 20GB (루트 × 6) | 6 | 미미 |
| EBS gp3 10GB (OSD × 6) | 6 | 미미 |
| EBS gp3 20GB (GPFS × 2) | 2 | 미미 |
| **합계** | | **~$0.49/h** |

> 사용하지 않을 때 `bash destroy.sh`로 삭제. EC2 중지만으로는 EBS 비용 지속 발생.
