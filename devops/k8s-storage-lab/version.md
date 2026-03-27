● 인프라 구성에 적용된 모든 구성요소의 버전 정보를 수집했습니다:

  1. IaC 및 클라우드 인프라

  위치: opentofu/main.tf:1-9
  - OpenTofu: >= 1.6.0
  - AWS Provider: ~> 5.0 (hashicorp/aws)
  - OS: Ubuntu 24.04 LTS (Noble Numbat)
    - AMI 필터: ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*
    - Owner: 099720109477 (Canonical)

  2. EC2 인스턴스 타입

  위치: opentofu/modules/ec2/main.tf
  - Bastion: t3.small (Ansible 제어 노드)
  - Master: t3.large (2 vCPU, 8GB RAM)
  - Worker: m5.large (2 vCPU, 8GB RAM) - HCI 구성
  - NSD: t3.large (2 vCPU, 8GB RAM) - GPFS 전용

  3. 스토리지 구성

  - EBS 볼륨 타입: gp3
  - Root 볼륨: 20GB (모든 인스턴스 공통)
  - Ceph OSD: 워커당 2개, 각 10GB
  - GPFS LUN: NSD당 1개씩, 총 2개

  4. Kubernetes 스택

  위치: ansible/inventory/group_vars/all.yml
  - Kubernetes: 1.31
  - kubeadm API: kubeadm.k8s.io/v1beta3
  - kube-proxy:
    - 모드: nftables
    - API: kubeproxy.config.k8s.io/v1alpha1
  - CNI: Flannel (master branch 최신)
    - 모드: VXLAN
    - 포트: UDP 8472
    - POD CIDR: 10.244.0.0/16
    - 소스: https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
  - kubectl: 1.31 (Kubernetes 버전과 일치)
  - kubelet: 1.31
  - kubeadm: 1.31

  5. Ceph 스토리지 스택

  위치: scripts/install/01_ceph_install.sh:9-10
  - Rook-Ceph Operator: v1.16.6
    - Helm repository: https://charts.rook.io/release
    - Chart: rook-release/rook-ceph
  - Ceph: v19.2.3
    - Image: quay.io/ceph/ceph:v19.2.3
  - Ceph API: ceph.rook.io/v1
  - 복제 설정:
    - osd_pool_default_size: 2
    - osd_pool_default_min_size: 1
    - Block Pool replicated size: 2
  - MON: 3개 (quorum 구성)
  - MGR: 1개
    - Module: pg_autoscaler (활성화)
  - Dashboard: 활성화 (SSL 비활성화)
  - MDS: activeCount=1, activeStandby=false
  - Toolbox: https://raw.githubusercontent.com/rook/rook/v1.16.6/deploy/examples/toolbox.yaml

  6. IBM Spectrum Scale (GPFS)

  위치: ansible/roles/gpfs_install/, scripts/install/03_csi_gpfs.sh
  - IBM Spectrum Scale: Developer Edition
  - 패키지 형식: .deb (Ubuntu용)
    - gpfs.base
    - gpfs.gpl
    - gpfs.adv
    - gpfs.crypto
    - gpfs.ext
  - CSI Driver: ibm-spectrum-scale-csi-operator
    - Repository: https://raw.githubusercontent.com/IBM/ibm-spectrum-scale-csi/master/stable/ibm-spectrum-scale-csi-operator
  - GUI:
    - Port: 443
    - secureSslMode: false
  - Filesystem: gpfs0
  - Cluster ID: gpfslab

  7. 자동화 및 관리 도구

  위치: opentofu/modules/ec2/user_data/bastion.sh:8-14
  - Python: 3.12.x (Ubuntu 24.04 기본)
    - 패키지: python3, python3-pip, pipx
    - 참고: https://documentation.ubuntu.com/ubuntu-for-developers/reference/availability/python/
  - Ansible: ansible-core 2.20.x (pipx를 통한 최신 stable)
    - 설치 방법: pipx install ansible-core
    - Python 요구사항: >= 3.12
    - 추가 의존성: boto3, botocore (pipx inject 방식)
    - 참고: https://docs.ansible.com/projects/ansible/latest/reference_appendices/release_and_maintenance.html
  - Ansible Collections:
    - amazon.aws
    - ansible.posix
    - community.general (>= 12.0.0, callback plugin 제거됨)
    - community.crypto
  - Ansible 설정 (ansible.cfg):
    - stdout_callback: ansible.builtin.default
    - result_format: yaml (ansible-core 2.13+ 방식)
  - Helm: v3+ (최신)
    - 설치: https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  - jq: 최신 (스크립트에서 사용)

  8. StorageClass

  - ceph-rbd:
    - Provisioner: rook-ceph.rbd.csi.ceph.com
    - Access Mode: RWO
    - Image Format: 2
    - Image Features: layering
  - ceph-cephfs:
    - Provisioner: rook-ceph.cephfs.csi.ceph.com
    - Access Mode: RWX
    - Filesystem: labfs
  - gpfs-scale:
    - Provisioner: spectrumscale.csi.ibm.com
    - Access Mode: RWX
    - Backend FS: gpfs0

  9. 시스템 패키지 (Ubuntu 24.04 기본 또는 명시적 설치)

  - Container Runtime: containerd (Ubuntu 패키지 기본)
  - 워커 노드 추가 패키지:
    - lvm2 (Ceph OSD용)
    - chrony (시간 동기화)
    - linux-modules-extra-aws (rbd 커널 모듈용)
  - GPFS 의존성:
    - ksh
    - perl
    - libaio1t64
    - libssl-dev
    - linux-headers-$(uname -r)
    - build-essential
    - dkms
  - 공통 패키지:
    - apt-transport-https
    - ca-certificates
    - curl
    - gpg

  10. 네트워크 구성

  - VPC CIDR: 변수로 설정 (기본값 확인 필요)
  - Subnet:
    - Bastion 서브넷: 별도
    - K8s 서브넷: 10.0.1.0/24
    - NSD 서브넷: 10.0.2.0/24
  - 보안 그룹:
    - Bastion SG
    - K8s HCI SG (k8s + Ceph 포트 통합)
    - NSD SG (GPFS)

  11. 커널 모듈

  자동 로드 설정 (modules-load.d):
  - overlay
  - br_netfilter
  - nf_tables
  - nft_masq
  - rbd
  - ceph

  이 버전 정보들은 코드 수정 시 다음 용도로 활용할 수 있습니다:
  1. 호환성 체크: Kubernetes 1.31 ↔ Rook v1.16.6 ↔ Ceph v19.2.3 간 호환성
  2. API 버전 검증: kubeadm v1beta3, kube-proxy v1alpha1 등
  3. 업그레이드 경로: 각 컴포넌트별 마이그레이션 가이드 참조
  4. 버그 픽스 확인: 특정 버전의 알려진 이슈 및 해결책 조회