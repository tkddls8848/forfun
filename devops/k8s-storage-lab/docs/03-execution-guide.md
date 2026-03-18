# 03. 단계별 실행 가이드

## 실행 흐름 요약
```
terraform.tfvars 수정 → start.sh → (GPFS 수동) → K8s → CSI → 테스트
```

| 단계 | 스크립트 | 소요시간(예상) | 자동/수동 |
|------|---------|---------------|-----------|
| 0 | `start.sh` → `tofu apply` | 3~5분 | 자동 |
| 0.5 | `00_hosts_setup.sh` | 2~3분 | 자동 (start.sh 포함) |
| 1 | `01_ceph_install.sh` | 5~10분 | 자동 (start.sh 포함) |
| 2 | `02_gpfs_install.sh` | 10~15분 | **수동** (IBM 패키지 필요) |
| 3 | `03_nsd_setup.sh` | 3~5분 | 수동 |
| 4 | `04_k8s_install.sh` | 5~10분 | 수동 |
| 5 | `05_csi_ceph.sh` | 3~5분 | 수동 |
| 6 | `06_csi_gpfs.sh` | 3~5분 | 수동 |
| 7 | `99_test_pvc.sh` | 2~3분 | 수동 |

**총 예상 시간: 35~60분**

---

## Step 0: 인프라 프로비저닝

### 0-1. terraform.tfvars 수정
```bash
cd opentofu/
vi terraform.tfvars
```

반드시 변경할 항목:
```hcl
key_name = "my-actual-keypair"   # AWS에 등록된 Key Pair 이름
```

### 0-2. 원클릭 시작
```bash
cd ..
SSH_KEY_PATH=~/.ssh/my-actual-keypair.pem ./start.sh
```

`start.sh`는 다음을 순서대로 실행합니다:
1. `tofu init` + `tofu apply` → EC2 11대 + EBS 8개 생성
2. 30초 부팅 대기 후 `00_hosts_setup.sh` → /etc/hosts, SSH 키 배포
3. `01_ceph_install.sh` → Ceph 클러스터 자동 구성

### 0-3. 결과 확인
```bash
cd opentofu/
tofu output
```

모든 Public/Private IP가 출력되면 성공입니다.

---

## Step 1: Ceph 클러스터 (start.sh에 포함)

`start.sh` 실행 시 자동으로 완료됩니다. 수동 확인:
```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<ceph-1-public-ip>
sudo ceph status
sudo ceph osd tree
sudo ceph df
```

정상이면 `HEALTH_OK` 또는 `HEALTH_WARN` (초기 안정화 중) 표시.

---

## Step 2: GPFS 설치 (수동)

### 2-1. IBM 패키지 다운로드

1. [IBM Developer Edition 다운로드 페이지](https://www.ibm.com/account/reg/us-en/signup?formid=urx-41728)에서 등록
2. `.deb` 패키지 다운로드
3. 프로젝트 루트에 배치:
```bash
mkdir -p gpfs-packages/
# 다운로드한 .deb 파일들을 여기에 복사
ls gpfs-packages/
# gpfs.base_*.deb  gpfs.gpl_*.deb  gpfs.adv_*.deb  gpfs.crypto_*.deb  gpfs.ext_*.deb
```

### 2-2. 설치 실행
```bash
bash scripts/02_gpfs_install.sh
```

K8s + NSD 전체 8개 노드에 GPFS 패키지를 전송하고 설치합니다.

---

## Step 3: NSD 구성 (수동)
```bash
bash scripts/03_nsd_setup.sh
```

수행 내용:
- GPFS 클러스터 생성 (gpfslab)
- NSD 디스크 정의 (EBS /dev/xvdb)
- 파일시스템 생성 (gpfs0)
- 전 노드 데몬 시작 + 마운트

확인:
```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<nsd-1-public-ip>
df -h | grep gpfs
sudo /usr/lpp/mmfs/bin/mmlsmount gpfs0 -L
```

---

## Step 4: Kubernetes 클러스터 (수동)
```bash
bash scripts/04_k8s_install.sh
```

수행 내용:
- kubeadm/kubelet/kubectl v1.29 설치
- Master-1 초기화 (HA endpoint)
- Master-2,3 control-plane join
- Worker-1,2,3 join
- Calico CNI 설치
- NSD 노드 taint 적용

확인:
```bash
export KUBECONFIG=~/.kube/config-k8s-storage-lab
kubectl get nodes -o wide
```

모든 노드가 `Ready` 상태여야 합니다.

---

## Step 5: Ceph CSI 설치 (수동)
```bash
bash scripts/05_csi_ceph.sh
```

확인:
```bash
kubectl get storageclass
# NAME          PROVISIONER           RECLAIMPOLICY
# ceph-rbd      rbd.csi.ceph.com      Delete
# ceph-cephfs   cephfs.csi.ceph.com   Delete
```

---

## Step 6: GPFS CSI 설치 (수동)
```bash
bash scripts/06_csi_gpfs.sh
```

확인:
```bash
kubectl get storageclass
# NAME          PROVISIONER                    RECLAIMPOLICY
# ceph-rbd      rbd.csi.ceph.com               Delete
# ceph-cephfs   cephfs.csi.ceph.com            Delete
# gpfs-scale    spectrumscale.csi.ibm.com      Delete
```

---

## Step 7: 통합 테스트
```bash
bash scripts/99_test_pvc.sh
```

3개 StorageClass 각각에 PVC + Pod를 생성하여 바인딩과 I/O를 검증합니다.

성공 기준:
- 3개 PVC 모두 `Bound` 상태
- 3개 Pod 모두 로그에 `OK` 출력

테스트 후 정리:
```bash
kubectl delete pod test-pod-rbd test-pod-cephfs test-pod-gpfs
kubectl delete pvc test-pvc-rbd test-pvc-cephfs test-pvc-gpfs
```

---

## 환경 종료
```bash
# EC2 중지 (EBS 스냅샷 보존, 비용 절감)
./stop.sh snapshot

# 전체 삭제 (되돌릴 수 없음)
./stop.sh destroy
```