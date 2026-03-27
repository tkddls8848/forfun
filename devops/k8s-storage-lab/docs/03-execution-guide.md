# 03. 단계별 실행 가이드

## 사전 요구사항

| 항목 | 조건 |
|------|------|
| AWS CLI | v2, 자격증명 설정 완료 |
| OpenTofu | v1.6+ |
| jq | 설치 필요 |
| SSH Key Pair | AWS에 등록, `~/.ssh/storage-lab.pem` 배치 |

> Windows 사용자: **WSL2**에서 실행. PEM 키를 WSL 홈으로 복사 후 `chmod 400`.

---

## 실행 흐름 요약

```
terraform.tfvars 수정
       ↓
bash start_k8s.sh          ← 인프라 + K8s + NSD 편입 (약 20~25분)
       ↓
bash start_ceph.sh         ← rook-ceph (약 15~20분)
       ↓
ansible-playbook haproxy.yml   ← Bastion HAProxy (선택)
       ↓
(선택) GPFS 수동 설치
ansible-playbook gpfs.yml
       ↓
kubectl apply -f manifests/test-pvc/
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
1. `[0/5]` 사전 요구사항 확인 (tofu, aws, jq, ssh)
2. `[1/5]` `tofu init` + `tofu apply` → EC2 7대 + EBS 8개 생성
3. `[2/5]` Bastion SSH 대기
4. `[3/5]` SSH 키 + ansible/ + manifests/ 전송
5. `[4/5]` 전체 노드 부팅 대기 (ProxyJump 통해 확인)
6. `[5/5]` `ansible-playbook k8s.yml` 실행:
   - common → worker → nsd → cluster_setup
   - kubernetes_common (master + worker + **nsd**)
   - kubernetes_master → CNI → kubernetes_worker
   - **kubernetes_nsd** (NSD K8s join + taint)
   - addons (Metrics Server, Dashboard, Prometheus, Grafana, MetalLB)

완료 후 확인 (Bastion에서):
```bash
export KUBECONFIG=~/.kube/config-k8s-storage-lab
kubectl get nodes -o wide
# master-1, worker-1~3, nsd-1~2 모두 Ready
# nsd 노드에 taint: role=gpfs-nsd:NoSchedule 확인
kubectl describe node nsd-1 | grep Taint
```

---

## Step 2: rook-ceph 구성

```bash
bash start_ceph.sh
```

내부 실행 순서:
1. Helm 설치 (master-1)
2. rook-ceph operator 배포 + 안정화 대기(60s)
3. rbd 커널 모듈 확인
4. CephCluster CR 배포 (useAllDevices: true, OSD 자동 감지)
5. OSD 안정화 대기 (5회 연속 동일 수)
6. HEALTH_OK 대기
7. rook-ceph-tools 배포
8. StorageClass 생성 (ceph-rbd, ceph-cephfs)
9. Dashboard 접속 정보 출력

완료 후 확인:
```bash
kubectl -n rook-ceph get pods -o wide
kubectl get storageclass
# ceph-rbd, ceph-cephfs 확인
```

---

## Step 3: HAProxy 설치 (선택)

K8s API 서버 단일 진입점 구성. master 증설 시 backend 자동 반영.

Bastion에서:
```bash
cd ~/ansible
/home/ubuntu/.local/bin/ansible-playbook \
  -i inventory/aws_ec2.yml playbooks/haproxy.yml
```

완료 후:
- `https://<bastion_public_ip>:6443` 으로 kubectl 접근 가능
- `http://<bastion_public_ip>:9000/stats` 통계 페이지 (admin/admin)

로컬 kubeconfig 설정:
```bash
kubectl config set-cluster k8s-storage-lab \
  --server=https://<bastion_public_ip>:6443
```

---

## Step 4: GPFS 설치 (IBM 패키지 필요)

```bash
# 1. IBM Developer Edition .deb 패키지를 gpfs-packages/ 에 배치
ls gpfs-packages/

# 2. Bastion에서 실행
ansible-playbook -i ansible/inventory/ ansible/playbooks/gpfs.yml
```

내부 실행 순서:
1. GPFS 패키지 설치 (master + worker + nsd 전체)
2. GPFS 클러스터 생성 (mmcrcluster, mmcrnsd, mmcrfs, mmmount)
3. **GPFS DaemonSet 배포** (`manifests/gpfs/gpfs-daemonset.yaml`) — K8s가 GPFS 데몬 관리
4. IBM Spectrum Scale CSI Helm 설치
5. StorageClass 생성 (gpfs-scale)

완료 후 확인:
```bash
kubectl get pods -n gpfs-system
# gpfs-daemon-xxxxx Running (nsd-1, nsd-2)
kubectl get storageclass
# gpfs-scale 확인
```

---

## Step 5: PVC 테스트

```bash
kubectl apply -f manifests/test-pvc/
kubectl get pvc
# ceph-rbd-pvc, ceph-cephfs-pvc, gpfs-pvc 모두 Bound
```

---

## 재설치 및 삭제

```bash
# rook-ceph만 재설치
bash destroy_ceph.sh && bash start_ceph.sh

# GPFS 해체
bash destroy_gpfs.sh

# 전체 삭제
bash destroy.sh
```

---

## EC2 중지/재시작 (비용 절감)

```bash
# 중지 (OSD 스냅샷 후 EC2 중지)
bash pause.sh

# 재시작 (IP 갱신 후 ansible + manifests 재전송)
bash resume.sh
```

---

## 예상 비용 (ap-northeast-2, 실행 중 기준)

| 리소스 | 수량 | 시간당 |
|--------|------|--------|
| t3.small (bastion × 1) | 1 | ~$0.026 |
| t3.large (master × 1) | 1 | ~$0.083 |
| m5.large (worker × 3) | 3 | ~$0.288 |
| t3.large (nsd × 2) | 2 | ~$0.166 |
| EBS gp2 10GB (루트 × 7) | 7 | 미미 |
| EBS gp2 10GB (OSD × 6) | 6 | 미미 |
| EBS gp2 10GB (GPFS × 2) | 2 | 미미 |
| **합계** | | **~$0.56/h** |

> 사용하지 않을 때 `bash pause.sh`로 중지하거나 `bash destroy.sh`로 삭제.
