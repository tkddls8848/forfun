# OS 구성별 호환성 검토

검토 대상: `devops/systems/*` 13개 시스템 + `AI/openclaw`
검토 기준일: 2026-08-11 / 기준 커밋: `2f843fe`

각 시스템이 **선언한 OS**와 **프로비저닝 코드가 실제로 가정하는 OS/커널/패키지 매니저**가
일치하는지, 그리고 호스트 OS(개발자 PC) 쪽 전제가 충족 가능한지를 점검했다.

---

## 1. OS 구성 인벤토리

| 시스템 | 게스트 OS (선언 위치) | 프로비저너 | 패키지 매니저 | 기본 사용자 |
| --- | --- | --- | --- | --- |
| `aws-k3s-storage-lab` | RHEL 9.7 (`packer/.../variables.pkrvars.hcl` = `ami-0a67d323f227ce006`, `opentofu/main.tf` = `RHEL-9.*_HVM-*`) | Packer + ssh 셸 | `dnf` | `ec2-user` |
| `aws-kubeadm-storage-lab` | Ubuntu 24.04 noble (`opentofu/main.tf` owner `099720109477`) | Packer + Ansible | `apt` | `ubuntu` |
| `AI/openclaw` | Ubuntu 24.04 (`variables.tf` 하드코딩 `ami-04f851a80be515079`) | `user_data` | `apt` | `ubuntu` |
| `local-ceph-kvm` | `cloud-image/ubuntu-24.04` (libvirt) | Vagrant 셸 | `apt` + **podman** | `vagrant` |
| `local-ceph-vagrant` | `bento/ubuntu-24.04` (VirtualBox) | Vagrant 셸 | `apt` + **docker** | `vagrant` |
| `local-hadoop-vagrant` | `bento/ubuntu-24.04` | Vagrant 셸 | `apt` | `vagrant` |
| `local-kubeadm-vagrant` | `bento/ubuntu-22.04` | Vagrant 셸 | `apt` | `vagrant` |
| `local-kubespray-rook-ceph` | `bento/ubuntu-24.04` | Vagrant 셸 | `apt` | `vagrant` |
| `local-kubespray-cephfs-centos8` | `generic/centos8` | Vagrant 셸 | `yum`/`dnf` | `vagrant` |
| `local-minikube-kubevirt-centos8` | `generic/centos8` | Vagrant 셸 | `dnf` | `vagrant` |
| `local-minikube-kubevirt-rocky` | `generic/rocky8` | Vagrant 셸 | `dnf` | `vagrant` |
| `local-kubeadm-gpu` | 호스트 Ubuntu + VM `noble-server-cloudimg-amd64` | 셸 + cloud-init | `apt` | `ubuntu` |
| `local-microk8s-kubeflow-gpu` | 호스트 Ubuntu (snap 필수) | 셸 | `apt` + `snap` | 호스트 사용자 |
| `local-k3s-ai` | **선언 없음** | 셸 | 없음 (`get.k3s.io`) | 호스트 사용자 |

패키지 매니저 자체의 오사용(예: RHEL 랩에서 `apt` 호출)은 **발견되지 않았다.**
문제는 아래의 다른 층위에 있다.

---

## 2. 치명적 결함 (Blocker)

### B-1. Windows CP949 왜곡으로 셸 스크립트 16개가 구문 오류 — 두 AWS 랩 모두 실행 불가

전체 셸 스크립트 100개 중 **16개가 `bash -n` 구문 검사에서 실패**한다.

```
$ for f in $(git ls-files '*.sh'); do bash -n "$f" 2>/dev/null || echo "$f"; done
devops/systems/aws-k3s-storage-lab/scripts/lifecycle/restart.sh
devops/systems/aws-k3s-storage-lab/scripts/lifecycle/rollback_1_infra.sh
devops/systems/aws-k3s-storage-lab/scripts/lifecycle/start_1_infra_k3s.sh
devops/systems/aws-k3s-storage-lab/scripts/lifecycle/start_2_ceph.sh
devops/systems/aws-k3s-storage-lab/scripts/lifecycle/start_3_beegfs.sh
devops/systems/aws-k3s-storage-lab/scripts/provision/00_build_ami.sh
devops/systems/aws-kubeadm-storage-lab/scripts/lifecycle/destroy_beegfs.sh
devops/systems/aws-kubeadm-storage-lab/scripts/lifecycle/destroy_ceph.sh
devops/systems/aws-kubeadm-storage-lab/scripts/lifecycle/pause.sh
devops/systems/aws-kubeadm-storage-lab/scripts/lifecycle/resume.sh
devops/systems/aws-kubeadm-storage-lab/scripts/lifecycle/start_beegfs.sh
devops/systems/aws-kubeadm-storage-lab/scripts/lifecycle/start_ceph.sh
devops/systems/aws-kubeadm-storage-lab/scripts/lifecycle/start_k8s.sh
devops/systems/aws-kubeadm-storage-lab/scripts/lifecycle/worker_remove.sh
devops/systems/aws-kubeadm-storage-lab/scripts/provision/00_build_ami.sh
devops/systems/aws-kubeadm-storage-lab/scripts/system/ceph_install.sh
```

**원인.** 이 파일들은 UTF-8 한글이 CP949(Windows 한국어 코드페이지)로 한 번
왕복 저장되면서 손실 변환됐다. 표현 불가 문자가 `?`(0x3F)로 치환되는 과정에서
**한글에 인접한 ASCII 인용부호와 괄호까지 함께 소실**됐다.

`start_1_infra_k3s.sh:52` 원본/현재:

```bash
echo " [2/3] SSH 연결 대기"     # 원본 의도
echo " [2/3] SSH ?<C2><B0>결 ?<C2><B0>?     # 현재 — 닫는 " 소실
...
  echo " ??                     # 원본 `echo " ✅"` — ✅ 와 닫는 " 가 함께 소실
done                            # → bash: syntax error near unexpected token `done'
```

`00_build_ami.sh:177`은 한글 소실로 `echo "[ 6 ] PEM ?<C2><B0>일 (로컬)"` 의
여는 따옴표가 앞 줄에서 이미 깨져, `(` 가 셸 문법으로 해석되며 실패한다.

**영향.** `devops/README.md`가 안내하는 **두 AWS 랩의 진입점이 모두 죽어 있다.**

| 시스템 | 문서상 시작 명령 | 실제 결과 |
| --- | --- | --- |
| `aws-k3s-storage-lab` | `bash scripts/lifecycle/start.sh` | `start.sh`는 정상이나 호출하는 3개 스테이지(`start_1_infra_k3s.sh`, `start_2_ceph.sh`, `start_3_beegfs.sh`)가 전부 구문 오류 |
| `aws-kubeadm-storage-lab` | `bash scripts/lifecycle/start_k8s.sh` | 진입점 자체가 구문 오류 (`line 82: syntax error near unexpected token 'done'`) |

롤백/정리 경로(`rollback_1_infra.sh`, `destroy_ceph.sh`, `destroy_beegfs.sh`)도 함께 깨져 있어
**부분 생성된 AWS 리소스를 스크립트로 회수할 수 없다** — 과금이 남는다.

**복구 난이도.** 손상은 비가역이다. 한글 본문 바이트가 `?`로 치환돼 원문을 복원할 수 없다.
구문만 살리려면 소실된 `"`/`)`를 수동으로 되돌려야 하고, 메시지 문구는 새로 작성해야 한다.

**추가 손상 파일(구문 오류는 없으나 한글이 깨진 상태):**
`aws-k3s-storage-lab/README.md`, `aws-kubeadm-storage-lab/README.md`,
`aws-kubeadm-storage-lab/docs/{02-scripts,03-execution-guide,04-troubleshooting,version}.md`,
`devops/docs/kubernetes-review-fix-list.md`, 각 랩의 `stop.sh`/`destroy.sh`/`worker_add.sh` 등.
총 30개 파일이 `iconv -f UTF-8` 검증에 실패한다.

**권고.**
1. 16개 스크립트의 구문 복구 + 메시지 재작성 (한글 재작성 불가피).
2. `.gitattributes`에 `eol=lf`는 있으나 **인코딩 강제 수단은 없다.** Windows 편집 시
   에디터를 UTF-8로 고정하고, `bash -n`을 pre-commit/CI 게이트로 추가할 것.
   현 상태에서는 동일 사고가 재발해도 커밋이 통과한다.

---

### B-2. CentOS 8 EOL — 2개 랩이 `vagrant up` 첫 프로비저닝에서 중단

- `local-kubespray-cephfs-centos8/Vagrantfile:27,45` → `sudo yum -y update`
- `local-minikube-kubevirt-centos8/Vagrantfile:19` → `sudo dnf update -y`

CentOS Linux 8은 2021-12-31 EOL이며 `mirrorlist.centos.org`가 응답하지 않는다.
`generic/centos8` 박스는 여전히 다운로드되지만 첫 `yum update`가
`Failed to download metadata for repo 'appstream'`로 실패한다.
두 Vagrantfile 모두 이 provision에 `|| true`가 없어 **`vagrant up` 전체가 중단**된다.

이후 단계도 연쇄로 불가능하다:
- `common/config.sh:29` → `dnf install -y iproute-tc`
- `master_node/kubespray.sh:12` → `dnf install -y git gcc zlib-devel ...` (Python 3.11 소스 빌드용)
- `scripts/cluster/minikube.sh:9` → `dnf -y install dnf-plugins-core`

**권고.** `vault.centos.org`로 리포지터리를 전환하거나(비권장, 보안 패치 없음),
쌍둥이 랩인 `local-minikube-kubevirt-rocky`(`generic/rocky8`, 2029년까지 지원)로
통합하고 CentOS 8 랩 2개는 아카이브 처리. `devops/README.md` 표에도 EOL 표기가 없다.

---

## 3. 높은 위험 (High)

### H-1. `local-kubespray-rook-ceph` — Ruby 히어독이 `\b`를 백스페이스로 변환, swap 비활성화가 무효

`Vagrantfile:47-53`:

```ruby
cfg.vm.provision "shell", privileged: true, inline: <<-SHELL
  ...
  sed -i '/\bswap\b/s/^[^#]/#&/' /etc/fstab
SHELL
```

종료자가 인용되지 않은 `<<-SHELL` 히어독은 **Ruby에서 큰따옴표 문자열처럼 이스케이프를
해석**한다. `\b`는 정규식 단어 경계가 아니라 **백스페이스(0x08)** 로 치환된다:

```
$ ruby -e 'x = <<-SHELL
sed -i "/\bswap\b/s/^[^#]/#&/" /etc/fstab
SHELL
puts x.bytes.select{|b| b<32 && b!=10}.inspect'
[8, 8]
```

게스트에 전달되는 실제 명령은 `sed -i '/<BS>swap<BS>/s/...'` 이며 어떤 줄에도 매치되지 않는다.
→ `/etc/fstab`의 swap 항목이 주석 처리되지 않고, **재부팅 후 swap이 되살아나 kubelet이 실패**한다.

이 두 줄은 커밋 `2f843fe`("Harden swap handling")가 추가한 것으로, 의도한 하드닝이
이 랩에서만 무효화됐다. 동일 패턴이 `.sh` 파일 안에 있을 때는 정상이다
(셸이 GNU sed에 그대로 넘기므로) — Ruby 히어독 안에 있는 이 한 곳만 문제다.

**수정.** 종료자를 인용해 이스케이프 해석을 끄거나(`<<-'SHELL'`), `\\b`로 이스케이프.
`<<-'SHELL'`은 이 인라인 블록에 변수 보간이 없어 안전하다.

### H-2. `aws-k3s-storage-lab` — RHEL 9에 podman이 설치되지 않음

`packer/k3s-storage-lab/scripts/backend.sh:5` 주석:

> `podman은 RHEL 9 기본 포함 — 별도 설치 불필요`

그러나 랩 전체에서 podman/docker를 설치하는 코드가 **한 줄도 없다**:

```
$ grep -rn "podman\|docker" devops/systems/aws-k3s-storage-lab --include=*.sh --include=*.hcl \
    | grep -i "install\|dnf\|yum"
(결과 없음)
```

`02_ceph_backend.sh`는 `podman ps -aq`(153행)와 `cephadm bootstrap`(159행)을 실행한다.
`cephadm` RPM은 컨테이너 엔진에 대한 하드 의존성이 없고 런타임에 탐색하므로,
podman이 없으면 부트스트랩 단계에서 실패한다.

RHEL 9 공식 클라우드 이미지는 `container-tools` 모듈을 기본 설치하지 않는다.
(네트워크 제약으로 해당 AMI를 직접 부팅해 확인하지는 못했다 — **미검증 가정**으로 표시한다.)

**권고.** `backend.sh`에 `dnf install -y podman`을 명시적으로 추가한다. 이미 포함돼
있더라도 멱등이며, 주석의 암묵 가정을 코드로 고정하는 편이 안전하다.

### H-3. VirtualBox 호스트 전용 네트워크 대역 제한 — 3개 랩이 기본 허용 범위 밖

VirtualBox 6.1.28 이상은 호스트 전용 네트워크를 **`192.168.56.0/21`(192.168.56.0–192.168.63.255)**
로 제한하며, 그 밖의 대역은 `/etc/vbox/networks.conf`(Windows는
`C:\ProgramData\VirtualBox\networks.conf`)에 명시적으로 허용해야 한다.

| 시스템 | 선언 IP | 판정 |
| --- | --- | --- |
| `local-kubeadm-vagrant` | 192.168.56.10–12 | 허용 범위 내 ✅ |
| `local-kubespray-rook-ceph` | 192.168.56.10–23 | 허용 범위 내 ✅ |
| `local-ceph-vagrant` | 192.168.60.x / 192.168.61.x | 허용 범위 내 ✅ |
| `local-hadoop-vagrant` | **192.168.70.10/21/22** | 범위 밖 ❌ |
| `local-minikube-kubevirt-centos8` | **192.168.81.10** | 범위 밖 ❌ |
| `local-minikube-kubevirt-rocky` | **192.168.81.10** | 범위 밖 ❌ |
| `local-kubespray-cephfs-centos8` | **192.168.1.10/21-23** | 범위 밖 ❌ |

범위 밖 랩은 호스트 OS(Linux/macOS/Windows 무관)에서
`Error: nonexistent host networking interface` 또는
`the specified IP is not within the allowed ranges`로 실패한다.

`local-kubespray-cephfs-centos8`의 `192.168.1.0/24`는 추가로 **가정용 공유기 LAN 대역과
충돌**할 가능성이 높다.

**권고.** IP를 `192.168.56.0/21` 안으로 이전하거나, 각 랩 README에
`networks.conf` 설정 절차를 사전 요구사항으로 명시한다.

### H-4. `aws-k3s-storage-lab` — RHEL AMI가 두 곳에서 서로 다르게 지정됨

| 위치 | 지정 방식 |
| --- | --- |
| `packer/k3s-storage-lab/variables.pkrvars.hcl:2` | `ami-0a67d323f227ce006` (RHEL 9.7, 고정) |
| `opentofu/main.tf:15-30` | `most_recent = true`, `RHEL-9.*_HVM-*-x86_64-*` (부동) |

Packer AMI를 쓰지 않는 경로(`ami_frontend`/`ami_backend` 미지정 시 `coalesce`가
`data.aws_ami.rhel9.id`로 폴백, `modules/ec2/main.tf:3,25`)에서는 **RHEL 9.x 마이너
버전이 실행 시점마다 달라진다.**

이 랩은 커널에 강하게 결합돼 있다 — `frontend.sh:42`가
`dnf install -y "kernel-devel-$(uname -r)"`로 BeeGFS 커널 모듈을 빌드하고
`/lib/modules/$(uname -r)/updates/...`에 설치한다. 마이너 버전이 바뀌면
`base_ami`로 빌드한 AMI의 사전 빌드 `beegfs.ko`와 실행 노드 커널이 어긋나
`04_csi_beegfs.sh:469`의 폴백 빌드 경로로 떨어진다.

또한 RHEL AMI는 RHUI를 통해 패키지를 받는데, RHUI는 통상 **최신 커널의 `kernel-devel`만
보유**한다. AMI 릴리스와 리포지터리 사이에 커널 갱신이 끼면
`kernel-devel-$(uname -r)`가 아예 설치되지 않는다 (`04_csi_beegfs.sh:471-475`가 이 경우를
이미 오류로 처리하고 있어, 저자도 인지한 위험으로 보인다).

**권고.** `opentofu/main.tf`의 `data.aws_ami.rhel9`를 `RHEL-9.7*`로 좁히거나
`variables.pkrvars.hcl`과 동일한 AMI ID를 `terraform.tfvars`에 고정한다.

---

## 4. 중간 위험 (Medium)

### M-1. `aws-kubeadm-storage-lab` — 커널 6.8 고정과 `linux-headers-aws` 메타패키지 충돌 가능성

`ansible/roles/hci_node/defaults/main.yml:6-7`과 `packer/scripts/worker.sh:57`이
worker에 `linux-headers-aws`, `linux-modules-extra-aws`를 설치한다. 이들은 **항상 최신
커널을 따라가는 메타패키지**다.

반면 `worker_kernel.sh:26-33`(및 `beegfs_prep/tasks/kernel_pin.yml`)이 APT preference로
6.8 이외 커널을 차단한다:

```
Package: linux-image-*-aws linux-headers-*-aws linux-modules-*-aws linux-modules-extra-*-aws
Pin: release *
Pin-Priority: -1
```

glob `linux-headers-*-aws`는 버전 없는 메타패키지 `linux-headers-aws`와 매치되지 않는다
(`linux-headers-` + `*` + `-aws` 구조상 `linux-headers--aws`가 필요). 따라서 메타패키지는
차단되지 않으면서, 그것이 의존하는 실제 버전 패키지는 우선순위 -1로 차단된다 →
`apt`가 의존성을 해소하지 못하거나 예상 밖 버전을 끌어올 수 있다.

Packer 빌드가 현재 성공한다면 apt가 기설치 버전으로 만족시키고 있을 가능성이 크다.
**확정 결함이 아니라 잠재 충돌**로 분류한다. `k8s.yml:24-38`의 커널 6.8 assert 게이트가
사후 방어선 역할을 하므로 조용한 실패는 아니다.

**권고.** preference의 `Package:` 목록에 `linux-headers-aws linux-modules-extra-aws`
(버전 없는 이름)를 명시적으로 추가하거나, 해당 메타패키지 설치를 6.8 고정 버전 패키지로 대체.

### M-2. `local-ceph-kvm` — libvirt 프로바이더의 `/vagrant` 동기화 전제가 문서화되지 않음

`scripts/ceph/cephadm-setup.sh:40`:

```bash
key_path="$(find "/vagrant/.vagrant/machines/$host" -path '*/private_key' -type f | head -n 1 || true)"
```

VirtualBox 쌍둥이 랩(`local-ceph-vagrant`)에서는 `/vagrant`가 자동 공유되지만,
`vagrant-libvirt`는 VirtualBox 공유 폴더를 쓸 수 없어 기본 동기화가 **NFS**다.
호스트에 `nfs-kernel-server`가 필요하고, `vagrant up` 중 sudo 권한과 방화벽 개방을 요구한다.
`local-ceph-kvm/Vagrantfile`에는 `config.vm.synced_folder` 선언이 전혀 없고,
`devops/README.md`의 시작 명령도 `vagrant up --provider=libvirt` 한 줄뿐이다.

`/vagrant`가 마운트되지 않으면 위 `find`가 빈 결과를 내고 스크립트가
`Missing Vagrant private key for ...`로 중단된다 (에러 처리 자체는 되어 있음).

**권고.** README에 NFS 사전 요구사항을 명시하거나 `type: "9p"` / `virtiofs`를 명시 선언.

### M-3. 쌍둥이 랩 간 하드닝 드리프트 — `local-ceph-kvm`이 `local-ceph-vagrant`의 수정을 못 받음

커밋 `2f843fe`가 `local-ceph-vagrant/scripts/ceph/cephadm-setup.sh`에 추가한
"OSD 디바이스 zap 후 Available 재확인" 로직(약 24줄)이 `local-ceph-kvm` 쪽에는 없다:

```
$ diff local-ceph-kvm/scripts/ceph/cephadm-setup.sh local-ceph-vagrant/scripts/ceph/cephadm-setup.sh
14c14
<   OSD_DEVICES_CSV="${6:-/dev/vdb,/dev/vdc}"      # virtio (KVM)
---
>   OSD_DEVICES_CSV="${6:-/dev/sdb,/dev/sdc}"      # SATA (VirtualBox)
100,101c100,126
<   (zap 로직 없음)
```

디바이스 이름 차이(`vd*` vs `sd*`)는 **올바른 OS 계층 대응**이다 —
`common-setup.sh:139`도 두 패턴을 모두 확인하도록 되어 있다.
문제는 zap 하드닝만 한쪽에 적용된 점이다. libvirt는 `vagrant destroy` 시 스토리지를
정리하므로 재현 확률은 VirtualBox(`.vdi` 잔존)보다 낮지만, `--no-destroy-on-error`나
수동 중단 후 재프로비저닝에서는 동일 증상이 발생한다.

`devops/README.md`의 "여러 시스템에서 같은 설치 코드가 필요하면 각 시스템 폴더에 복제한다"
정책상 이런 드리프트는 구조적으로 반복된다. 복제 파일 간 동기화 점검 절차가 필요하다.

### M-4. `aws-kubeadm-storage-lab` — Python 3.12 하드코딩으로 noble 외 이식 불가

- `ansible/inventory/group_vars/all.yml:4` → `ansible_python_interpreter: /usr/bin/python3.12`
- `ansible/roles/node_base/tasks/packages.yml:22`, `packer/scripts/base.sh:12` → `python3.12` 패키지 명시

Ubuntu 22.04(3.10)나 25.04(3.13)에서는 인터프리터 경로가 존재하지 않아 모든 태스크가
`/usr/bin/python3.12: not found`로 실패한다. `ansible.cfg`에 `interpreter_python = auto_silent`가
설정돼 있으므로 group_vars의 하드코딩을 제거하면 자동 탐색이 동작한다.

동일 계열로 `node_base/tasks/containerd.yml:3,10`이 Docker의 **Ubuntu 전용 경로**
(`download.docker.com/linux/ubuntu`)를 쓰므로 Debian/RHEL 이식이 불가능하다.
현재 이 랩은 Ubuntu 전용이라 결함은 아니나, `docs/05-onpremises-migration.md`가
온프레미스 이전을 다루고 있어 이식 시 걸림돌이 된다.

### M-5. CentOS 8 랩 — NetworkManager 비활성화가 네트워크를 끊을 수 있음

`local-kubespray-cephfs-centos8/common/config.sh:15-16`:

```bash
sudo systemctl stop NetworkManager 2>/dev/null || true
sudo systemctl disable NetworkManager 2>/dev/null || true
```

RHEL/CentOS 8부터 `network-scripts`(구 `initscripts`)는 기본 미설치이며 NetworkManager가
유일한 네트워크 관리자다. 이를 비활성화하면 **재부팅 후 인터페이스가 올라오지 않는다.**
같은 스크립트가 `/etc/resolv.conf`를 직접 덮어쓰는 것(31-33행)도 NM이 없어야 유지되는
방식이라, 의도한 동작과 부작용이 얽혀 있다.

B-2로 인해 이 랩은 어차피 실행되지 않지만, 랩을 Rocky 8/9로 이전할 경우
이 코드를 그대로 옮기면 동일 문제가 재현된다.

---

## 5. 낮은 위험 (Low) / 정리 대상

| # | 위치 | 내용 |
| --- | --- | --- |
| L-1 | `local-hadoop-vagrant/scripts/common.sh:8,44` | `JAVA_HOME=/usr/lib/jvm/java-17-openjdk-**amd64**` 하드코딩. `bento/ubuntu-24.04`는 arm64 변종(Parallels/VMware, Apple Silicon)도 제공하므로 해당 호스트에서 Hadoop 기동 실패. `$(dirname $(readlink -f $(which javac)))/..` 방식 권장 |
| L-2 | `local-minikube-kubevirt-centos8/scripts/cluster/minikube.sh:8` | 주석이 `## install docker (no docker in Rocky Linux)` — rocky 랩에서 복사된 흔적. 두 파일은 바이트 단위로 동일하며 CentOS 8 랩에 맞는 설명이 아님 |
| L-3 | `aws-k3s-storage-lab/packer/.../base.sh:9`, `aws-kubeadm-storage-lab/packer/scripts/base.sh:8` | `sed -i '/swap/d' /etc/fstab` — "swap" 문자열이 포함된 무관한 줄까지 삭제. 로컬 랩들은 이미 `/\bswap\b/s/^[^#]/#&/`로 하드닝됐으나 AWS 랩 2개만 옛 패턴 잔존. AWS AMI에는 swap 항목이 없어 현재는 무해 |
| L-4 | `aws-k3s-storage-lab/packer/.../frontend.sh:17` | `k3s-selinux-1.6-1.el9.noarch.rpm` URL 하드코딩. Rancher가 버전을 올리면 404 → 뒤의 `|| dnf install -y k3s-selinux \|\| true` 폴백이 조용히 삼킨다. SELinux enforcing인 RHEL 9에서 `--selinux` 플래그와 함께 k3s가 기동 실패할 수 있음 |
| L-5 | `local-k3s-ai` | 지원 OS/배포판이 어디에도 선언돼 있지 않음. `scripts/addons/ai.sh`는 systemd + `sudo`만 가정하므로 실제로는 광범위하게 동작하나, README 표의 "호스트 K3s"만으로는 사전 요구사항을 알 수 없음 |
| L-6 | `AI/openclaw/opentofu/variables.tf:60` | `default = "ami-04f851a80be515079" # Ubuntu 24.04 LTS (서울, 확인 필요)` — 주석이 스스로 미검증임을 표시. AMI ID는 리전 종속이며 폐기될 수 있음. 같은 파일 주석에 있는 `describe-images` 쿼리를 `data "aws_ami"`로 옮기면 해결 |
| L-7 | `local-microk8s-kubeflow-gpu/scripts/cluster/03_...sh:11` | `systemctl is-active snapd` 전제. snap이 없는 배포판(RHEL/Debian 최소 설치)에서는 스크립트가 snapd 설치를 시도하지 않고 실패. "Ubuntu 호스트" 전제를 README에 명시 필요 |

---

## 6. 정상 확인 항목

검토 과정에서 **문제 없음**으로 확인한 항목들:

- 패키지 매니저와 게스트 OS의 대응 — 14개 시스템 전부 일치 (RHEL 랩은 `dnf`만, Ubuntu 랩은 `apt`만)
- SSH 기본 사용자 — RHEL `ec2-user`, Ubuntu `ubuntu`, Vagrant `vagrant`로 각 랩 내부 일관
  (`packer/*.pkr.hcl`의 `ssh_username`과 시스템 스크립트의 `ssh ...@` 대상이 모두 일치)
- 디바이스 명명 규칙의 OS 계층 대응 — libvirt `vd*` / VirtualBox `sd*` / AWS Nitro `nvme*n1`을
  각각 올바르게 구분. 특히 Nitro의 비결정적 NVMe 번호 문제를 EBS volume serial
  (`/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol...`) 및 `nvme id-ctrl` 조회로 해소한
  방식(`02_ceph_backend.sh:197-208`, `beegfs_prep/tasks/main.yml`)은 정확하다
- Ubuntu 24.04 nftables 대응 — `node_base/tasks/kernel_modules.yml`이 `nf_tables`/`nft_masq`를
  등록하고 `local-kubeadm-gpu/00_host_setup.sh`가 libvirt `firewall_backend = "nftables"`를
  설정하는 것은 noble 기본값에 맞는 올바른 처리
- BeeGFS 버전별 커널 제약 대응 — 7.4.6(커널 ≤6.11) → Ubuntu worker 6.8 고정,
  8.3(RHEL 9 기본 5.14 지원) → 고정 불필요. 두 랩의 선택이 각 OS에 맞게 분기돼 있음
- `.gitattributes`의 `eol=lf` 강제 — CRLF 혼입은 발견되지 않음 (인코딩은 별개 문제, B-1 참조)

---

## 7. 조치 우선순위

| 순위 | 항목 | 근거 |
| --- | --- | --- |
| 1 | B-1 셸 스크립트 16개 구문 복구 + `bash -n` CI 게이트 | 두 AWS 랩이 실행·정리 모두 불가, 리소스 회수 경로까지 손상 |
| 2 | H-2 RHEL 9 `podman` 명시 설치 | 한 줄 추가로 해소, 미검증이나 실패 시 랩 전체 중단 |
| 3 | H-1 Vagrantfile 히어독 `<<-'SHELL'` | 한 글자 수정, swap 하드닝 의도 복원 |
| 4 | H-3 VirtualBox IP 대역 이전 또는 문서화 | 3개 랩이 호스트 무관하게 기동 불가 |
| 5 | B-2 CentOS 8 랩 처리 방침 결정 (Rocky 이전 / 아카이브) | 복구 아닌 정책 결정 사안 |
| 6 | H-4 RHEL AMI 버전 고정 | 재현성 확보 |
| 7 | M-1 ~ M-5 | 잠재 결함 및 이식성 |
| 8 | L-1 ~ L-7 | 정리 |
