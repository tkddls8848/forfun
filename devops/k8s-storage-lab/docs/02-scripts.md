# 02. 셸 스크립트 구조

## 진입점 스크립트 (프로젝트 루트)

| 파일 | 역할 |
|------|------|
| `start_k8s.sh` | 인프라 생성 + K8s 클러스터 구성 (00~01 순차 실행) |
| `start_ceph.sh` | rook-ceph 설치 (02 실행) |
| `destroy_ceph.sh` | rook-ceph만 삭제 + OSD 디스크 초기화 |
| `destroy.sh` | 전체 AWS 리소스 삭제 (tofu destroy) |

---

## scripts/.env

`00_hosts_setup.sh` 실행 시 자동 생성. 이후 모든 스크립트가 `source scripts/.env`로 로드.

```bash
M1_PUB=<master-1 공인 IP>
M1_PRIV=<master-1 사설 IP>
WORKER_PUBS=(ip1 ip2 ip3)      # 배열 — worker_count 동적 반영
WORKER_PRIVS=(ip1 ip2 ip3)
N1_PUB=<nsd-1 공인 IP>; N2_PUB=<nsd-2 공인 IP>
N1_PRIV=<nsd-1 사설 IP>; N2_PRIV=<nsd-2 사설 IP>
SSH_KEY=~/.ssh/storage-lab.pem
```

---

## 00_hosts_setup.sh

1. `tofu output`으로 모든 IP 수집 (worker 배열 동적 처리)
2. SSH 접속 확인 루프 (부팅 완료 대기)
3. `/etc/hosts` 전 노드 배포
4. 클러스터 내부 SSH 키 생성 및 배포 (master-1 → 전 노드)
5. `scripts/.env` 생성

---

## 01_k8s_install.sh

1. **cloud-init 완료 대기** — `cloud-init status --wait` + SSH 재연결 루프
   - user_data에서 패키지 설치 + reboot 발생 → 재접속 확인 필수
2. **hostname 설정** — kubeadm이 hostname을 노드명으로 등록
3. **kubeadm/kubelet/kubectl 설치** (K8s 1.31)
4. **Master-1 초기화** — `kubeadm init --config kubeadm-config.yaml`
   - `KubeProxyConfiguration mode: nftables` 적용 (Ubuntu 24.04 필수)
   - kube-proxy 모드 적용 여부 검증
5. **Worker join** (순차) — 노드 등록 확인 후 다음 노드 진행
6. **Flannel CNI** (VXLAN, UDP 8472)
7. **kubeconfig** 로컬 저장 (`~/.kube/config-k8s-storage-lab`)

### kube-proxy nftables 모드 적용 이유

Ubuntu 24.04는 nftables 네이티브 환경. kube-proxy 기본값(iptables 모드)으로 기동 시
Flannel과 `/run/xtables.lock` 경합 → kube-proxy CrashLoopBackOff → 클러스터 네트워킹 단절.
K8s 1.31에서 nftables 모드 GA, `kubeadm init` 시 config 파일로 기본 적용.

---

## 02_ceph_install.sh

1. **Helm 설치** (master-1)
2. **rook-ceph Helm repo 추가** + namespace 생성
3. **rook-ceph Operator 배포** — rollout 완료 후 60초 CRD watch 안정화 대기
4. **워커 rbd 모듈 로드 확인** — 미로드 시 `modprobe rbd`
5. **CephCluster CR 배포** — worker 1대씩 순차 추가 (I/O 스파이크 방지)
   - `useAllDevices: true` (EBS 자동 감지)
   - `osd_pool_default_size: "2"`, `osd_pool_default_min_size: "1"`
   - placement: control-plane 제외 (worker only)
6. **Ceph HEALTH_OK 대기**
7. **rook-ceph-tools toolbox 배포**
8. **CephBlockPool + StorageClass (ceph-rbd, RWO)**
9. **CephFilesystem + StorageClass (ceph-cephfs, RWX)**

### OSD 순차 초기화 이유

일제 초기화 시 모든 worker에서 동시에 OSD I/O 발생 → etcd 과부하 → API server 응답 지연.
worker 1대씩 OSD Running 확인 후 다음 노드 추가.

---

## 03_csi_ceph.sh

StorageClass 확인 스크립트 (검증 용도).

---

## 04_gpfs_install.sh

IBM Spectrum Scale .deb 패키지를 NSD 서버에 전송 및 설치.
`gpfs-packages/` 디렉토리에 패키지 배치 후 실행.

---

## 05_nsd_setup.sh

1. GPFS 클러스터 생성
2. NSD 디스크 정의 (EBS /dev/xvdb)
3. 파일시스템 생성 및 마운트

---

## 06_csi_gpfs.sh

IBM Spectrum Scale CSI Helm 차트 설치 → StorageClass `gpfs-scale` 생성.

---

## 99_test_pvc.sh

3개 StorageClass에 PVC + Pod 생성하여 동적 프로비저닝 및 I/O 검증.

- `ceph-rbd` (RWO) — Dynamic Provisioning
- `ceph-cephfs` (RWX) — Dynamic Provisioning
- `gpfs-scale` (RWX) — Dynamic Provisioning

> StorageClass 지정만으로 PV 수동 생성 없이 자동 볼륨 생성됨 (Dynamic Provisioning).

---

## destroy_ceph.sh

API 서버 연결 여부를 먼저 확인 후 K8s 단계를 조건부 실행.

```
[1/5] API 서버 연결 확인    → 미응답 시 [2~4] 스킵
[2/5] StorageClass 삭제
[3/5] CephFilesystem / BlockPool 삭제
[4/5] CephCluster 삭제 (finalizer 제거) + Helm uninstall + namespace + CRD 삭제
[5/5] 워커 OSD 디스크 초기화 (sgdisk + dd + dmsetup + pvremove)  ← 항상 실행
```

---

## destroy.sh

```bash
# .env에서 IP 미리 수집 → tofu destroy → 로컬 정리
source scripts/.env
tofu destroy -auto-approve
rm -f scripts/.env ~/.kube/config-k8s-storage-lab
ssh-keygen -R <각 노드 IP>   # known_hosts 정리
```
