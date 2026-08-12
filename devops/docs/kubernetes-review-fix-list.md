# k8s 클러스터 정의 코드 수정 필요 목록

검토 범위: `D:\forfun\devops\k8s` 하위 전체 클러스터 정의 코드.

원칙:

- 기존 방식과 신규 방식을 동시에 살리는 완충 구현은 넣지 않는다.
- 클러스터 유형별로 표준적인 한 가지 구현 방식을 선택하고, 충돌하거나 위험한 기존 경로는 제거한다.
- 노드 간 작업은 직접 SSH 명령으로 처리하지 않는다. 단, `kvm/ubuntu/kubeadm/gpu`는 예외로 둔다.
- 노드 간 작업은 Ansible inventory에 master/worker/storage 역할을 정의하고, Ansible playbook이 각 대상 노드에서 실행하는 방식으로 통일한다. 단, `kvm/ubuntu/kubeadm/gpu`는 예외로 둔다.
- CNI는 클러스터 유형별로 명시한다. MicroK8s를 제외한 Kubernetes 클러스터는 Flannel로 전환한다. MicroK8s는 기본 CNI를 유지한다.
- 버전은 latest가 아니라 os 버전 및 k8s 버전 및 관련 설치요소간 호환성이 가장 안정적인 버전을 선택한다.
- `kvm/ubuntu/kubeadm/gpu`는 예외로 둔다. 기존 VM 생성/SSH 기반 흐름은 유지하되, 위험한 cleanup과 latest 사용은 제거하고 필요한 이유를 문서화한다.



## 치명적 수정 항목

- [ ] `ubuntu/kubeadm/Vagrantfile`의 kubeadm 공통 프로비저닝 스크립트 경로를 수정한다.
  - 현재 호출: `./kubeadm-common.sh`
  - 실제 존재 파일: `./kubeadm-setup.sh`
  - 수정 요청: Vagrantfile의 shell provision path를 실제 파일명인 `./kubeadm-setup.sh`로 변경하고, 이후 인자 순서가 `kubeadm-setup.sh`의 기대값과 일치하는지 검증한다.


- [ ] `vagrant/ubuntu/kubeadm/basic`의 kubeadm 인자 계약을 수정한다.
  - `kubeadm-setup.sh`는 `KUBE_VERSION`을 기대하지만 Vagrantfile은 전달하지 않고 있고 `kubeadm-master.sh`는 `KUBE_VERSION`, `CALICO_VERSION`을 기대하지만 Vagrantfile은 전달하지 않는다.
  - 수정 요청: MicroK8s를 제외한 Kubernetes 클러스터의 CNI를 Flannel로 통일한다. `vagrant/ubuntu/kubeadm/basic`은 Calico 관련 인자를 제거하고, Ansible inventory 또는 group vars에서 Kubernetes 버전과 Flannel 버전을 명시해 넘긴다.


- [ ] 클러스터 설정 방식에서 password/root SSH를 제거한다.
  - 대상:
    - `ubuntu/kubeadm/kubeadm-setup.sh`
    - `ubuntu/kubeadm/kubeadm-master.sh`
    - `ubuntu/kubespray/kubespray.sh`
    - `ubuntu/cephadm/scripts/ceph/common-setup.sh`
    - `ubuntu/cephadm/scripts/ceph/cephadm-setup.sh`
    - `kvm/cephadm/scripts/ceph/common-setup.sh`
    - `kvm/cephadm/scripts/ceph/cephadm-setup.sh`
    - `centos8/cephfs/common/config.sh`
    - `centos8/cephfs/master_node/kubespray.sh`
  - 현재 문제: `PermitRootLogin yes`, `PasswordAuthentication yes`, `sshpass`, `expect`, 하드코딩된 `vagrant` 비밀번호, `StrictHostKeyChecking=no`가 기본 경로에 포함되어 있다.
  - 수정 요청: 노드 간 작업에 대해 ansible 인벤토리로 접근한다.

- [ ] Ceph OSD 디스크 초기화를 명시 디스크 대상으로 제한한다.
  - 대상:
    - `ubuntu/cephadm/scripts/ceph/cephadm-setup.sh`
    - `kvm/cephadm/scripts/ceph/cephadm-setup.sh`
  - 현재 문제: `vd[b-z]`, `sd[b-z]` 전체를 순회하며 `sgdisk --zap-all`을 실행한다.
  - 수정 요청: inventory 또는 group vars에 OSD 디스크 목록을 선언하고, 선언된 디스크만 wipe한다. 선언되지 않은 디스크가 발견되면 자동 처리하지 말고 경고 또는 실패로 끝낸다.


- [ ] 로컬 런타임 상태 파일을 정리하고 ignore 상태를 확인한다.
  - 대상:
    - `ubuntu/cephadm/.vagrant`
    - `kvm/cephadm/.vagrant`
    - `kvm/cephadm/.claude/settings.local.json`
    - `kvm/kubeadm_GPU/.claude/settings.local.json`
  - 현재 상태: 해당 경로는 로컬에는 존재하지만 `.gitignore`에 의해 ignore되고 있으며, 현재 `git ls-files` 기준으로 추적되지는 않는다.
  - 수정 요청: 로컬 상태 파일은 저장소 산출물에서 제외한다. 추적 중인 항목이 발견되면 `git rm --cached`로 추적만 제거하고, `.gitignore`가 계속 차단하는지 `git check-ignore -v`로 검증한다.

- [ ] 클러스터별 Ansible inventory를 추가한다.
  - 대상:
    - `vagrant/ubuntu/kubeadm/basic`
    - `vagrant/ubuntu/kubespray/rook-ceph`
    - `../storage/vagrant/ubuntu/cephadm/basic`
    - `../storage/kvm/ubuntu/cephadm/basic`
    - `../storage/vagrant/centos8/cephfs/kubespray`
  - 현재 문제: 노드 이름, IP, 역할, worker 수, storage/gpu 여부가 Vagrantfile과 스크립트 내부 값으로 흩어져 있다.
  - 수정 요청: 클러스터별 `inventory.yml` 또는 `inventory.ini`를 추가하고 `control_plane`, `workers`, `storage` 같은 그룹을 정의한다. 노드 수, IP, 역할, 버전, 네트워크 대역 등 클러스터 설정 정보는 Ansible inventory 또는 group vars에서 단일 기준으로 관리한다. `kvm/ubuntu/kubeadm/gpu`는 예외로 두고 기존 스크립트 흐름을 문서화한다.


## 높은 우선순위의 정확성 수정

- [ ] `../storage/vagrant/ubuntu/cephadm/basic`와 `../storage/kvm/ubuntu/cephadm/basic`의 차이를 명확히 문서화한다.
  - 대상:
    - `../storage/vagrant/ubuntu/cephadm/basic`
    - `../storage/kvm/ubuntu/cephadm/basic`
  - 현재 문제: 두 클러스터 정의의 Ceph 스크립트와 부가 파일이 유사하지만, provider와 실행 환경 차이가 문서에서 명확히 드러나지 않는다.
  - 수정 요청: 두 구현은 별도 클러스터 정의로 유지한다. 다만 `../storage/vagrant/ubuntu/cephadm/basic`와 `../storage/kvm/ubuntu/cephadm/basic`의 provider, VM 디스크 방식, 네트워크, inventory, 실행 전제 차이를 README 또는 각 클러스터 문서에 명확히 적는다.

- [ ] Kubespray worker 수와 인벤토리 생성을 일치시킨다.
  - 대상:
    - `ubuntu/kubespray/Vagrantfile`
    - `ubuntu/kubespray/kubespray.sh`
  - 현재 문제: `NODE_NUMBER = K8S_CLUSTER.size()`는 master까지 포함하지만, inventory는 worker 3개로 하드코딩되어 있다.
  - 수정 요청: 정보를 ansible 인벤토리에서 전체 통합 관리한다.


- [ ] Kubespray 프로비저닝을 재실행 가능하게 정리한다.
  - 대상: `ubuntu/kubespray/kubespray.sh`
  - 현재 문제: `ssh-keygen`, `git clone`, inventory 복사, 패키지 설치를 기존 상태 확인 없이 항상 실행한다.
  - 수정 요청: SSH 키, Kubespray checkout, inventory, Python venv, 패키지 설치는 존재 여부와 버전을 확인한 뒤 필요한 경우에만 생성/갱신한다. 재실행 시 기존 정상 상태를 덮어쓰지 않도록 한다.


- [ ] 다운로드한 Kubernetes 매니페스트를 `sed`로 직접 수정하는 방식을 제거한다.
  - 대상:
    - `ubuntu/kubeadm/kubeadm-master.sh`
    - `ubuntu/kubespray/kubespray.sh`
    - `centos8/cephfs/master_node/kubespray.sh`
  - 현재 문제: Calico/MetalLB 매니페스트를 다운로드한 뒤 즉시 수정 또는 적용한다.
  - 수정 요청: MicroK8s를 제외한 Kubernetes 클러스터는 Flannel로 수정하고 지정된 k8s 버전 및 관련 요소 버전을 참고하여 가장 안정적인 버전으로 고정한다. 의도한 설정은 ansible 인벤토리를 이용한다.


- [ ] 외부 설치 파일의 `latest` 사용을 제거하고 버전을 고정한다.
  - 예시 대상:
    - `centos8/minikube/minikube.sh`
    - `rocky/minikube/minikube.sh`
    - `centos8/minikube/kubevirt/kubevirt_install.sh`
    - `centos8/minikube/kubevirt/kubevirt_run.sh`
    - `rocky/minikube/kubevirt/kubevirt_install.sh`
    - `rocky/minikube/kubevirt/kubevirt_run.sh`
    - `ubuntu/kubeadm/kubevirt/scripts/kubevirt-setup.sh`
    - `ubuntu/k3s/ai.sh`
    - `ubuntu/cephadm/scripts/ceph/monitoring-setup.sh`
    - `kvm/cephadm/scripts/ceph/monitoring-setup.sh`
    - `centos8/cephfs/master_node/kubespray.sh`
  - 수정 요청: 버전은 클러스터 정의된 k8s 버전 및 os 버전과의 호환성을 가장 안정적으로 지원하는 버전으로 고정한다.

## Kubernetes 구현 수정

- [ ] kubeadm 클러스터별 CNI를 하나로 명시한다.
  - 현재 상태: `vagrant/ubuntu/kubeadm/basic`은 Calico를 사용한다.
  - 현재 상태: `kvm/ubuntu/kubeadm/gpu`는 Flannel을 사용한다.
  - 수정 요청: MicroK8s를 제외한 Kubernetes 클러스터는 Flannel로 전환한다. `vagrant/ubuntu/kubeadm/basic`은 Calico를 제거하고 Flannel로 전환한다. `kvm/ubuntu/kubeadm/gpu`는 예외 원칙에 따라 기존 흐름은 유지하되 Flannel 매니페스트 버전만 고정한다. MicroK8s는 기본 CNI를 유지한다.

- [ ] `ubuntu/kubeadm/kubeadm-master.sh`에서 master가 password SSH로 worker join을 수행하는 방식을 제거한다.
  - 현재 문제: master가 worker를 순회하며 `ssh ... sudo kubeadm join`을 실행한다.
  - 수정 요청: 노드간 작업은 Ansible 인벤토리 방식으로 전달한다.

- [ ] root 비밀번호 변경과 sudoers 직접 append를 제거한다.
  - 대상:
    - `ubuntu/kubeadm/kubeadm-setup.sh`
    - `ubuntu/cephadm/scripts/ceph/common-setup.sh`
    - `ubuntu/cephadm/scripts/ceph/cephadm-setup.sh`
    - `kvm/cephadm/scripts/ceph/common-setup.sh`
    - `kvm/cephadm/scripts/ceph/cephadm-setup.sh`
    - `centos8/cephfs/common/config.sh`
  - 수정 요청: vagrant 기본 sudo만 쓰고, root 비밀번호 변경, root SSH 허용, password auth 허용, sudoers append는 제거

- [ ] kubeadm reset/destroy 동작은 rollback 스크립트로만 이동한다.
  - 대상:
    - `kvm/kubeadm_GPU/04_worker_join.sh`
    - `kvm/kubeadm_GPU/06_rollback.sh`
  - 현재 문제: worker join 경로에서 이전 kubeadm 상태를 발견하면 cleanup을 수행한다.
  - 수정 요청: 파괴적 reset은 rollback/destroy 흐름에만 둔다. 일반 join 경로에서는 실패를 명확히 반환한다.

- [ ] `kvm/kubeadm_GPU/02_node_setup.sh`의 NVIDIA runtime 수정 방식을 재검토한다.
  - 현재 문제: NVIDIA runtime config를 legacy mode로 바꾸고 containerd import 동작까지 수정한다.
  - 수정 요청: 이 클러스터는 예외로 두고 기존 설정 변경은 유지한다. 다만 legacy mode, disable-require, containerd imports 수정이 왜 필요한지 스크립트 주석과 README에 설명한다.

- [ ] `kvm/kubeadm_GPU/03_master_init.sh`의 Flannel 매니페스트 버전을 고정한다.
  - 현재 문제: `releases/latest/download/kube-flannel.yml`을 적용한다.
  - 수정 요청: Flannel 릴리스 버전을 변수로 고정하고, 해당 버전의 매니페스트를 저장소에 보관하거나 고정 URL로 적용한다. 가능하면 적용 전 checksum 또는 파일 존재 여부를 검증한다.

- [ ] MicroK8s/Kubeflow 버전과 네트워크 가정을 고정한다.
  - 대상:
    - `host/ubuntu/microk8s/kubeflow-gpu/scripts/cluster/03_microk8s_gpu_addon_install.sh`
    - `host/ubuntu/microk8s/kubeflow-gpu/scripts/cluster/04_juju_kubeflow_lite_install.sh`
  - 현재 문제: MicroK8s channel과 MetalLB IP range가 특정 호스트 네트워크에 하드코딩되어 있다.
  - 수정 요청: MicroK8s channel, Juju/Kubeflow 버전, MetalLB IP range를 클러스터 설정값으로 분리한다. MicroK8s CNI는 기본값을 유지하고, 호스트 네트워크에 맞지 않는 대역이면 설치 전에 실패하도록 검증한다.

## Ceph/Rook/storage 수정

- [ ] Ceph public network와 cluster network 선언을 정리한다.
  - 대상:
    - `ubuntu/cephadm/scripts/ceph/common-setup.sh`
    - `kvm/cephadm/scripts/ceph/common-setup.sh`
  - 현재 문제: `CEPH_PUBLIC_NETWORK`와 `CEPH_CLUSTER_NETWORK`가 같은 CIDR로 설정되어 있다.
  - 수정 요청: 프론트 네트워크와 백 네트워크 분리를 위해 실제 두 번째 네트워크를 추가한다.

- [ ] Ceph monitor/manager placement를 의도에 맞게 정리한다.
  - 대상:
    - `ubuntu/cephadm/Vagrantfile`
    - `kvm/cephadm/Vagrantfile`
  - 현재 상태: 작은 테스트 클러스터에서 `mon_count = 1`, `mgr_count = 2`를 사용한다.
  - 수정 요청: 단일 monitor 실습 클러스터이다. non-HA임을 명확히 문서화한다.

- [ ] Ceph OSD 적용에서 `--all-available-devices` 사용을 제거한다.
  - 대상:
    - `ubuntu/cephadm/scripts/ceph/cephadm-setup.sh`
    - `kvm/cephadm/scripts/ceph/cephadm-setup.sh`
  - 현재 문제: `ceph orch apply osd --all-available-devices`는 노드에서 사용 가능한 모든 디스크를 OSD 후보로 취급한다.
  - 수정 요청: Ansible inventory 또는 group vars에 선언한 OSD 디스크만 대상으로 OSD를 적용한다. Vagrant provider가 만든 디스크 외의 장치를 자동 대상으로 삼지 않는다.

- [ ] `ubuntu/kubespray/ceph-rook` 하위 Rook/Ceph 스크립트를 검토한다.
  - 대상:
    - `ubuntu/kubespray/ceph-rook.sh`
    - `ubuntu/kubespray/ceph-rook/ceph_block/ceph_blockstorage.sh`
    - `ubuntu/kubespray/ceph-rook/ceph_file/ceph_filesystem.sh`
    - `ubuntu/kubespray/ceph-rook/ceph-object/ceph_objectstorage.sh`
    - `centos8/cephfs/master_node/ceph.sh`
  - 수정 요청: Rook Operator / CephCluster / StorageClass / ObjectStore / Filesystem 매니페스트 버전을 고정한다. GitHub 관련 yaml 매니페스트는 저장소 안의 안정적 위치에 보관하고 `kubectl apply -f URL` 방식은 제거한다. `~/rook/deploy/examples`에 의존하지 말고 클러스터별 manifests 디렉터리에서 적용한다. 클러스터 네트워크, storage device, replica count, pool size가 실습 클러스터 규모와 맞는지 검토한다. block/file/object storage 설정이 서로 중복되거나 충돌하지 않도록 한다. StorageClass 이름이 기존 Kubernetes 리소스와 충돌하지 않는지 검토한다. Cephadm 방식과 Rook 방식이 같은 클러스터 안에서 섞여 있지 않은지 검토한다.

## 저장소 정리 항목

- [ ] 깨진 한글 주석과 echo 메시지를 복구한다.
  - 대상: `devops/local/kubernetes` 하위 대부분의 Vagrantfile과 shell script
  - 수정 요청: 깨진 인코딩 문자열은 UTF-8 한글 또는 명확한 영어 메시지로 복구한다. 실행 로그는 단계, 대상 노드, 실패 원인이 드러나도록 정리하고, 의미 없는 장식성 출력은 제거한다.

- [x] 생성물/로컬 상태에 대한 `.gitignore` 항목을 추가한다.
  - 이미 ignore 중인 패턴:
    - `.vagrant/`
    - `**/.claude`
    - `password.rb`
  - 추가 필요 패턴:
    - `devops/local/kubernetes/**/*.vdi`
    - `devops/local/kubernetes/**/*.vmdk`
    - `devops/local/kubernetes/**/*.qcow2`
    - `devops/local/kubernetes/**/*.img`
    - `devops/local/kubernetes/**/*.iso`
    - `devops/local/kubernetes/**/kubeconfig`
    - `devops/local/kubernetes/**/kubeconfig-*`
    - `devops/local/kubernetes/**/admin.conf`
    - `devops/local/kubernetes/**/join-command.sh`
    - `devops/local/kubernetes/**/worker_join.sh`
    - `devops/local/kubernetes/**/*.retry`
    - `devops/local/kubernetes/**/.ansible/`
    - `devops/local/kubernetes/**/.cache/`
    - `devops/local/kubernetes/**/tmp/`
    - `devops/local/kubernetes/**/rook/`
    - `devops/local/kubernetes/**/kubespray-repo/`
  - 현재 추적 중인 정리 검토 대상:
    - `ubuntu/hadoop/tmp/core-site.xml`
  - 처리 결과: 루트 `.gitignore`에 `devops/local/kubernetes` 경로 한정 패턴을 추가했다. 기존 `.vagrant/`, `**/.claude`, `password.rb` 중복 추가는 피했다.

- [x] 클러스터 정의와 무관한 앱 의존성 산출물을 정리한다.
  - 대상:
    - `examples/ubuntu-cephadm-share-object-app/package-lock.json`
    - `examples/kvm-cephadm-share-object-app/package-lock.json`
  - 처리 결과: Ceph 클러스터 정의와 샘플 애플리케이션을 분리하고 `examples/` 아래로 이동했다.

- [x] 디렉터리 이름 규칙을 통일한다.
  - 처리 결과: `Rocky`를 `rocky`로 변경했다.

- [x] `host/ubuntu/microk8s/kubeflow-gpu/scripts/lifecycle/destroy_cluster.sh` 오타를 수정한다.
  - 처리 결과: `destory_cluster.sh`를 `destroy_cluster.sh`로 변경했다.

- [x] `devops/local/kubernetes` 최상위 README를 추가한다.
  - 포함 내용:
    - 클러스터 목록
    - 클러스터별 지원 provider
    - 필요한 host 도구
    - 예상 네트워크 대역
    - Ansible inventory 위치
    - 생성/삭제 명령
    - non-HA/lab-only 가정
  - 처리 결과: `devops/local/kubernetes/README.md`를 추가하고 각 클러스터의 목적, 지원 provider, 네트워크, inventory 위치, 생성/삭제 명령, known limitations를 정리했다. `kvm/ubuntu/kubeadm/gpu`는 예외 클러스터임을 README에도 명시했다.

- [x] 검증 진입점을 추가한다.
  - 처리 결과: `devops/local/kubernetes/validate.ps1`를 추가했다. shellcheck, `vagrant validate`, `ansible-inventory --list`를 설치된 도구 기준으로 실행한다.

## 클러스터별 처리 방향

- [ ] `vagrant/ubuntu/kubeadm/basic`: 사용 전 수정 필수. 스크립트 경로 불일치와 누락된 버전 인자가 있다.

- [ ] `vagrant/ubuntu/kubespray/rook-ceph`: inventory/node count를 단일 소스로 만들고 password SSH 자동화를 제거한 뒤 사용한다.

- [ ] `../storage/vagrant/ubuntu/cephadm/basic`: 별도 클러스터 정의로 유지하고, 위험한 SSH 설정과 디스크 wipe 동작을 제거하며, `.vagrant`를 삭제한다. `../storage/kvm/ubuntu/cephadm/basic`와의 provider/디스크/네트워크 차이를 문서화한다.

- [ ] `../storage/kvm/ubuntu/cephadm/basic`: 별도 클러스터 정의로 유지하고, libvirt 전용 디스크/provider 전제를 문서화하며, `.vagrant`와 로컬 설정을 삭제한다.

- [ ] `kvm/ubuntu/kubeadm/gpu`: 예외 클러스터로 둔다. 기존 VM 생성/SSH 기반 동작은 유지하되 주석과 README로 이유를 문서화한다. Flannel 버전을 고정하며, 파괴적 cleanup은 rollback에만 둔다.

- [ ] `vagrant/centos8/minikube/kubevirt`: Minikube/KubeVirt 버전을 고정하고, OS별 차이를 문서화

- [ ] `../storage/vagrant/centos8/cephfs/kubespray`: `devops/local/kubernetes` 검토 대상에 포함한다. password SSH, sudoers append, expect 기반 Kubespray 자동화, Rook 예제 디렉터리 의존, 외부 디스크 경로 하드코딩을 제거하거나 Ansible inventory/group vars 기준으로 전환한다.

- [x] `vagrant/rocky/minikube/kubevirt`: `vagrant/centos8/minikube/kubevirt` OS별 차이를 문서화

- [ ] `vagrant/ubuntu/kubeadm/basic/scripts/addons/kubevirt`: KubeVirt 버전을 고정하고 GitHub API로 `latest`를 조회하는 방식을 제거한다.

- [ ] `host/ubuntu/microk8s/kubeflow-gpu`: channel/version을 고정하고, 네트워크 대역을 클러스터 정의값으로 관리하며, 일반 설치 흐름에서 광범위한 home/cache 삭제를 제거한다.

- [ ] `host/ubuntu/k3s/ai`: pipe-to-shell latest installer를 제거하고, 고정된 installer 버전과 명시 설치 옵션을 사용한다.

- [ ] `../data/vagrant/ubuntu/hadoop/basic`: Kubernetes 클러스터 정의가 아니라면 `k8s` 하위에서 이동한다. 유지한다면 목적과 실행 방식을 명확히 문서화한다.
