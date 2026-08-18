# DevOps Systems

이 저장소는 배포 가능한 시스템 하나를 `systems/`의 폴더 하나로 관리합니다.
환경·분야·OS를 여러 단계의 디렉터리로 나누지 않고 폴더명에 핵심 특징을 표시합니다.

```text
devops/
├── systems/
│   ├── aws-k3s-storage-lab/
│   ├── aws-kubeadm-storage-lab/
│   ├── local-ceph-kvm/
│   └── ...
└── docs/
```

각 명령은 해당 시스템 폴더에서 실행합니다. 시스템이 사용하는 앱과 설치 스크립트도
같은 폴더에 있으므로 다른 시스템 폴더를 참조하지 않습니다.

## 시스템 목록

| 폴더 | 구성 | 시작 명령 |
| --- | --- | --- |
| `aws-k3s-storage-lab` | AWS, K3s, Ceph, BeeGFS | `bash scripts/lifecycle/start.sh` |
| `aws-kubeadm-storage-lab` | AWS, kubeadm HA, Ceph, BeeGFS | `bash scripts/lifecycle/start_k8s.sh` |
| `local-ceph-kvm` | libvirt/KVM, Cephadm | `vagrant up --provider=libvirt` |
| `local-ceph-vagrant` | VirtualBox, Cephadm, Block Store 앱 | `vagrant up --provider=virtualbox` |
| `local-gostore-vagrant` | VirtualBox, Go 정적 바이너리 에이전트, xfs/ext4/tmpfs 지연 비교 | `bash scripts/build.sh && vagrant up` |
| `local-hadoop-vagrant` | VirtualBox, Hadoop | `vagrant up` |
| `local-k3s-ai` | 호스트 K3s, 선택적 K3ai | `bash scripts/addons/ai.sh` |
| `local-kubeadm-gpu` | libvirt/KVM, kubeadm, GPU | `bash 00_host_setup.sh` |
| `local-kubeadm-vagrant` | VirtualBox, kubeadm | `vagrant up` |
| `local-kubespray-cephfs-rocky9` | VirtualBox, Kubespray, CephFS, Rocky Linux 9 | `vagrant up` |
| `local-kubespray-rook-ceph` | VirtualBox, Kubespray, Rook/Ceph | `vagrant up` |
| `local-microk8s-kubeflow-gpu` | 호스트 MicroK8s, Kubeflow, GPU | `bash scripts/host/01_nvidia_driver_install.sh`부터 순서대로 실행 |
| `local-minikube-kubevirt-rocky` | VirtualBox, Minikube, KubeVirt, Rocky Linux 9 | `vagrant up` |

## 폴더 규칙

- 새 시스템은 `systems/<위치>-<핵심 기술>-<목적>` 형태로 추가합니다.
- 시스템 실행에 필요한 코드는 해당 폴더 안에 둡니다.
- 여러 시스템에서 같은 설치 코드가 필요하면 각 시스템 폴더에 복제합니다.
- 시스템 간 상대경로 참조는 만들지 않습니다.
- 생성 파일과 비밀정보는 각 시스템의 `.gitignore`에서 관리합니다.
