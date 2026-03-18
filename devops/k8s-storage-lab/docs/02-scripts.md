# 02. 셸 스크립트 전체 코드

## scripts/00_hosts_setup.sh
```bash
#!/bin/bash
set -e
cd "$(dirname "$0")/.."

export SSH_KEY="${SSH_KEY_PATH:-~/.ssh/id_rsa}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -i $SSH_KEY"

echo "=============================="
echo " Step 0: IP 수집 (tofu output)"
echo "=============================="

M1_PUB=$(tofu output -json master_public_ips  | jq -r '.[0]')
M2_PUB=$(tofu output -json master_public_ips  | jq -r '.[1]')
M3_PUB=$(tofu output -json master_public_ips  | jq -r '.[2]')
W1_PUB=$(tofu output -json worker_public_ips  | jq -r '.[0]')
W2_PUB=$(tofu output -json worker_public_ips  | jq -r '.[1]')
W3_PUB=$(tofu output -json worker_public_ips  | jq -r '.[2]')
N1_PUB=$(tofu output -json nsd_public_ips     | jq -r '.[0]')
N2_PUB=$(tofu output -json nsd_public_ips     | jq -r '.[1]')
C1_PUB=$(tofu output -json ceph_public_ips    | jq -r '.[0]')
C2_PUB=$(tofu output -json ceph_public_ips    | jq -r '.[1]')
C3_PUB=$(tofu output -json ceph_public_ips    | jq -r '.[2]')

M1_PRIV=$(tofu output -json master_private_ips | jq -r '.[0]')
M2_PRIV=$(tofu output -json master_private_ips | jq -r '.[1]')
M3_PRIV=$(tofu output -json master_private_ips | jq -r '.[2]')
W1_PRIV=$(tofu output -json worker_private_ips | jq -r '.[0]')
W2_PRIV=$(tofu output -json worker_private_ips | jq -r '.[1]')
W3_PRIV=$(tofu output -json worker_private_ips | jq -r '.[2]')
N1_PRIV=$(tofu output -json nsd_private_ips    | jq -r '.[0]')
N2_PRIV=$(tofu output -json nsd_private_ips    | jq -r '.[1]')
C1_PRIV=$(tofu output -json ceph_private_ips   | jq -r '.[0]')
C2_PRIV=$(tofu output -json ceph_private_ips   | jq -r '.[1]')
C3_PRIV=$(tofu output -json ceph_private_ips   | jq -r '.[2]')

ALL_PUB=($M1_PUB $M2_PUB $M3_PUB $W1_PUB $W2_PUB $W3_PUB $N1_PUB $N2_PUB $C1_PUB $C2_PUB $C3_PUB)

cat > scripts/.env <<EOF
M1_PUB=$M1_PUB; M2_PUB=$M2_PUB; M3_PUB=$M3_PUB
W1_PUB=$W1_PUB; W2_PUB=$W2_PUB; W3_PUB=$W3_PUB
N1_PUB=$N1_PUB; N2_PUB=$N2_PUB
C1_PUB=$C1_PUB; C2_PUB=$C2_PUB; C3_PUB=$C3_PUB
M1_PRIV=$M1_PRIV; M2_PRIV=$M2_PRIV; M3_PRIV=$M3_PRIV
W1_PRIV=$W1_PRIV; W2_PRIV=$W2_PRIV; W3_PRIV=$W3_PRIV
N1_PRIV=$N1_PRIV; N2_PRIV=$N2_PRIV
C1_PRIV=$C1_PRIV; C2_PRIV=$C2_PRIV; C3_PRIV=$C3_PRIV
SSH_KEY=$SSH_KEY
EOF

echo "=============================="
echo " Step 0-1: 노드 부팅 대기"
echo "=============================="
for ip in "${ALL_PUB[@]}"; do
  echo -n "  $ip 대기 중..."
  until ssh $SSH_OPTS ubuntu@$ip "echo ok" &>/dev/null; do
    echo -n "."; sleep 5
  done
  echo " ✓"
done

echo "=============================="
echo " Step 0-2: /etc/hosts 배포"
echo "=============================="
HOSTS=$(cat <<EOF
# k8s-storage-lab
$M1_PRIV  master-1
$M2_PRIV  master-2
$M3_PRIV  master-3
$W1_PRIV  worker-1
$W2_PRIV  worker-2
$W3_PRIV  worker-3
$N1_PRIV  nsd-1
$N2_PRIV  nsd-2
$C1_PRIV  ceph-1
$C2_PRIV  ceph-2
$C3_PRIV  ceph-3
EOF
)

for ip in "${ALL_PUB[@]}"; do
  ssh $SSH_OPTS ubuntu@$ip "echo '$HOSTS' | sudo tee -a /etc/hosts > /dev/null"
  echo "  /etc/hosts 업데이트: $ip"
done

echo "=============================="
echo " Step 0-3: 클러스터 내부 SSH 키 생성 및 배포"
echo "=============================="
ssh $SSH_OPTS ubuntu@$M1_PUB "
  [ -f ~/.ssh/id_rsa ] || ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -q
"
CLUSTER_PUBKEY=$(ssh $SSH_OPTS ubuntu@$M1_PUB "cat ~/.ssh/id_rsa.pub")

for ip in "${ALL_PUB[@]}"; do
  ssh $SSH_OPTS ubuntu@$ip "
    echo '$CLUSTER_PUBKEY' >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
  "
  echo "  SSH 키 배포: $ip"
done

echo ""
echo "✅ Step 0 완료 - 다음: scripts/01_ceph_install.sh"
```

---

## scripts/01_ceph_install.sh
```bash
#!/bin/bash
set -e
source scripts/.env

SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

echo "=============================="
echo " Step 1: cephadm 설치 (ceph-1)"
echo "=============================="
$CSSH$C1_PUB <<'ENDSSH'
  curl -fsSL https://download.ceph.com/keys/release.asc | sudo gpg --dearmor -o /etc/apt/keyrings/ceph.gpg
  echo "deb [signed-by=/etc/apt/keyrings/ceph.gpg] https://download.ceph.com/debian-reef/ $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/ceph.list
  sudo apt-get update -y
  sudo apt-get install -y cephadm
  sudo cephadm install
ENDSSH

echo "=============================="
echo " Step 1-1: Ceph 클러스터 Bootstrap"
echo "=============================="
CEPH1_PRIV_IP=$C1_PRIV
$CSSH$C1_PUB "sudo cephadm bootstrap \
  --mon-ip $CEPH1_PRIV_IP \
  --initial-dashboard-user admin \
  --initial-dashboard-password admin123! \
  --allow-overwrite \
  --skip-monitoring-stack"

echo "=============================="
echo " Step 1-2: ceph-2, ceph-3 노드 추가"
echo "=============================="
CEPH_PUBKEY=$($CSSH$C1_PUB "sudo cat /etc/ceph/ceph.pub")

for ip in $C2_PUB $C3_PUB; do
  ssh $SSH_OPTS ubuntu@$ip "echo '$CEPH_PUBKEY' | sudo tee -a /root/.ssh/authorized_keys"
done

$CSSH$C1_PUB "
  sudo ceph orch host add ceph-2 $C2_PRIV
  sudo ceph orch host add ceph-3 $C3_PRIV
  sleep 10
"

echo "=============================="
echo " Step 1-3: OSD 추가"
echo "=============================="
$CSSH$C1_PUB "
  sudo ceph orch apply osd --all-available-devices
  sleep 30
  sudo ceph osd tree
"

echo "=============================="
echo " Step 1-4: CephFS + RBD Pool 생성"
echo "=============================="
$CSSH$C1_PUB "
  sudo ceph osd pool create cephfs_data 32
  sudo ceph osd pool create cephfs_metadata 8
  sudo ceph fs new labfs cephfs_metadata cephfs_data

  sudo ceph osd pool create rbd 32
  sudo ceph osd pool application enable rbd rbd
  sudo rbd pool init rbd

  sudo ceph osd pool set cephfs_data size 2
  sudo ceph osd pool set cephfs_metadata size 2
  sudo ceph osd pool set rbd size 2

  echo '--- Ceph 상태 확인 ---'
  sudo ceph status
  sudo ceph df
"

echo "=============================="
echo " Step 1-5: CSI용 ceph 키 추출"
echo "=============================="
$CSSH$C1_PUB "
  sudo ceph auth get-or-create client.k8s \
    mon 'profile rbd' \
    osd 'profile rbd pool=rbd, profile rbd pool=cephfs_data' \
    mds 'allow rw' \
    > /tmp/ceph-client-k8s.keyring
  sudo cat /etc/ceph/ceph.conf
  sudo cat /tmp/ceph-client-k8s.keyring
" > /tmp/ceph-info.txt

echo ""
echo "✅ Step 1 완료 - Ceph 클러스터 구성 완료"
echo "   다음: scripts/02_gpfs_install.sh"
```

---

## scripts/02_gpfs_install.sh
```bash
#!/bin/bash
set -e
source scripts/.env

SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"
CSCP="scp $SSH_OPTS"

GPFS_PKG_DIR="./gpfs-packages"
if [ ! -d "$GPFS_PKG_DIR" ]; then
  echo "❌ $GPFS_PKG_DIR 디렉토리가 없습니다."
  echo "   IBM Spectrum Scale Developer Edition을 다운로드 후"
  echo "   $GPFS_PKG_DIR/ 에 .deb 패키지를 넣어주세요."
  echo "   다운로드: https://www.ibm.com/account/reg/us-en/signup?formid=urx-41728"
  exit 1
fi

ALL_NODES_PUB=($M1_PUB $M2_PUB $M3_PUB $W1_PUB $W2_PUB $W3_PUB $N1_PUB $N2_PUB)

echo "=============================="
echo " Step 2: GPFS 패키지 전송 및 설치"
echo "=============================="
for ip in "${ALL_NODES_PUB[@]}"; do
  echo "  패키지 전송 → $ip"
  $CSCP -r $GPFS_PKG_DIR ubuntu@$ip:/tmp/gpfs-packages

  echo "  GPFS 설치 → $ip"
  $CSSH$ip <<'ENDSSH'
    cd /tmp/gpfs-packages
    sudo apt-get install -y ksh perl libaio1 libssl-dev \
      linux-headers-$(uname -r) build-essential dkms

    sudo dpkg -i gpfs.base_*.deb       || true
    sudo dpkg -i gpfs.gpl_*.deb        || true
    sudo dpkg -i gpfs.adv_*.deb        || true
    sudo dpkg -i gpfs.crypto_*.deb     || true
    sudo dpkg -i gpfs.ext_*.deb        || true
    sudo apt-get install -f -y

    sudo /usr/lpp/mmfs/bin/mmbuildgpl
ENDSSH
  echo "  ✓ GPFS 설치 완료: $ip"
done

echo "=============================="
echo " Step 2-1: SSH 접근 확인"
echo "=============================="
$CSSH$N1_PUB "
  for host in master-1 master-2 master-3 worker-1 worker-2 worker-3 nsd-1 nsd-2; do
    ssh -o StrictHostKeyChecking=no ubuntu@\$host 'echo \$host ok' || echo \"WARN: \$host 접근 실패\"
  done
"

echo ""
echo "✅ Step 2 완료 - 다음: scripts/03_nsd_setup.sh"
```

---

## scripts/03_nsd_setup.sh
```bash
#!/bin/bash
set -e
source scripts/.env

SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

CLUSTER_NAME="gpfslab"
FS_NAME="gpfs0"
MOUNT_POINT="/gpfs/gpfs0"

echo "=============================="
echo " Step 3: GPFS 클러스터 생성"
echo "=============================="
$CSSH$N1_PUB "
  sudo tee /tmp/NodeFile <<EOF
nsd-1:quorum-manager
nsd-2:quorum-manager
master-1:quorum
master-2:quorum
master-3:quorum
worker-1:
worker-2:
worker-3:
EOF

  sudo /usr/lpp/mmfs/bin/mmcrcluster \
    -N /tmp/NodeFile \
    -C $CLUSTER_NAME \
    -p nsd-1 \
    -s nsd-2

  sudo /usr/lpp/mmfs/bin/mmchlicense client --accept \
    -N master-1,master-2,master-3,worker-1,worker-2,worker-3
  sudo /usr/lpp/mmfs/bin/mmchlicense server --accept \
    -N nsd-1,nsd-2

  echo '--- 클러스터 확인 ---'
  sudo /usr/lpp/mmfs/bin/mmlscluster
"

echo "=============================="
echo " Step 3-1: NSD 디스크 정의"
echo "=============================="
$CSSH$N1_PUB "
  sudo tee /tmp/NSDFile <<EOF
%nsd:
  device=/dev/xvdb
  nsd=nsd1disk
  servers=nsd-1,nsd-2
  usage=dataAndMetadata
  failureGroup=1

%nsd:
  device=/dev/xvdb
  nsd=nsd2disk
  servers=nsd-2,nsd-1
  usage=dataAndMetadata
  failureGroup=2
EOF

  sudo /usr/lpp/mmfs/bin/mmcrnsd -F /tmp/NSDFile
  echo '--- NSD 확인 ---'
  sudo /usr/lpp/mmfs/bin/mmlsnsd
"

echo "=============================="
echo " Step 3-2: GPFS 파일시스템 생성"
echo "=============================="
$CSSH$N1_PUB "
  sudo /usr/lpp/mmfs/bin/mmcrfs $FS_NAME \
    -F /tmp/NSDFile \
    -A yes \
    -B 256K \
    -m 2 -M 2 \
    -r 2 -R 2

  echo '--- 파일시스템 확인 ---'
  sudo /usr/lpp/mmfs/bin/mmlsfs $FS_NAME
"

echo "=============================="
echo " Step 3-3: GPFS 데몬 시작 및 마운트"
echo "=============================="
ALL_GPFS_PUB=($N1_PUB $N2_PUB $M1_PUB $M2_PUB $M3_PUB $W1_PUB $W2_PUB $W3_PUB)

for ip in "${ALL_GPFS_PUB[@]}"; do
  $CSSH$ip "sudo /usr/lpp/mmfs/bin/mmstartup"
  echo "  mmstartup: $ip"
done

sleep 15

$CSSH$N1_PUB "
  sudo /usr/lpp/mmfs/bin/mmgetstate -a
  sudo mkdir -p $MOUNT_POINT
  sudo /usr/lpp/mmfs/bin/mmmount $FS_NAME -a

  echo '--- 마운트 확인 ---'
  df -h | grep $FS_NAME
  sudo /usr/lpp/mmfs/bin/mmlsmount $FS_NAME -L
"

echo ""
echo "✅ Step 3 완료 - 마운트 포인트: $MOUNT_POINT"
echo "   다음: scripts/04_k8s_install.sh"
```

---

## scripts/04_k8s_install.sh
```bash
#!/bin/bash
set -e
source scripts/.env

SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

K8S_VERSION="1.29"
POD_CIDR="192.168.0.0/16"
CONTROL_PLANE_EP="$M1_PRIV:6443"

ALL_K8S_PUB=($M1_PUB $M2_PUB $M3_PUB $W1_PUB $W2_PUB $W3_PUB)

echo "=============================="
echo " Step 4: kubeadm 설치"
echo "=============================="
for ip in "${ALL_K8S_PUB[@]}"; do
  $CSSH$ip <<EOF
    sudo apt-get update -y
    sudo apt-get install -y apt-transport-https ca-certificates curl gpg

    curl -fsSL https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/Release.key | \
      sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
      https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/ /" | \
      sudo tee /etc/apt/sources.list.d/kubernetes.list

    sudo apt-get update -y
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    sudo systemctl enable --now kubelet
EOF
  echo "  ✓ kubeadm 설치: $ip"
done

echo "=============================="
echo " Step 4-1: Master-1 초기화"
echo "=============================="
$CSSH$M1_PUB "
  sudo kubeadm init \
    --control-plane-endpoint '$CONTROL_PLANE_EP' \
    --pod-network-cidr $POD_CIDR \
    --upload-certs \
    --v=5 2>&1 | tee /tmp/kubeadm-init.log

  mkdir -p \$HOME/.kube
  sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config
  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
"

echo "=============================="
echo " Step 4-2: join 명령어 추출"
echo "=============================="
MASTER_JOIN=$($CSSH$M1_PUB "sudo kubeadm token create --print-join-command --certificate-key \$(sudo kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)")
WORKER_JOIN=$($CSSH$M1_PUB "sudo kubeadm token create --print-join-command")

echo "=============================="
echo " Step 4-3: Master-2, Master-3 join"
echo "=============================="
for ip in $M2_PUB $M3_PUB; do
  $CSSH$ip "sudo $MASTER_JOIN --control-plane"
  $CSSH$ip "
    mkdir -p \$HOME/.kube
    sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config
    sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
  "
  echo "  ✓ Master join: $ip"
done

echo "=============================="
echo " Step 4-4: Worker join"
echo "=============================="
for ip in $W1_PUB $W2_PUB $W3_PUB; do
  $CSSH$ip "sudo $WORKER_JOIN"
  echo "  ✓ Worker join: $ip"
done

echo "=============================="
echo " Step 4-5: Calico CNI"
echo "=============================="
$CSSH$M1_PUB "
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

  kubectl wait --for=condition=Ready nodes --all --timeout=300s
  kubectl get nodes -o wide
"

echo "=============================="
echo " Step 4-6: NSD taint"
echo "=============================="
$CSSH$M1_PUB "
  kubectl taint nodes nsd-1 dedicated=gpfs-nsd:NoSchedule || true
  kubectl taint nodes nsd-2 dedicated=gpfs-nsd:NoSchedule || true
  kubectl label nodes nsd-1 role=nsd
  kubectl label nodes nsd-2 role=nsd
  kubectl get nodes
"

scp $SSH_OPTS ubuntu@$M1_PUB:~/.kube/config ~/.kube/config-k8s-storage-lab
echo ""
echo "✅ Step 4 완료 - kubeconfig → ~/.kube/config-k8s-storage-lab"
echo "   다음: scripts/05_csi_ceph.sh"
```

---

## scripts/05_csi_ceph.sh
```bash
#!/bin/bash
set -e
source scripts/.env

export KUBECONFIG=~/.kube/config-k8s-storage-lab
SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

echo "=============================="
echo " Step 5: Helm 설치"
echo "=============================="
$CSSH$M1_PUB "
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
"

echo "=============================="
echo " Step 5-1: ceph-csi Helm repo"
echo "=============================="
$CSSH$M1_PUB "
  helm repo add ceph-csi https://ceph.github.io/csi-charts
  helm repo update
  kubectl create namespace ceph-csi-rbd    || true
  kubectl create namespace ceph-csi-cephfs || true
"

CEPH_FSID=$($CSSH$C1_PUB "sudo ceph fsid")
CEPH_MON_IP=$C1_PRIV
CEPH_KEY=$($CSSH$C1_PUB "sudo ceph auth get-key client.k8s 2>/dev/null || sudo ceph auth get-or-create client.k8s mon 'profile rbd' osd 'profile rbd pool=rbd' | grep key | awk '{print \$3}'")

echo "=============================="
echo " Step 5-2: ceph-csi-rbd (Block)"
echo "=============================="
$CSSH$M1_PUB "
cat <<EOF > /tmp/csi-rbd-values.yaml
csiConfig:
  - clusterID: \"$CEPH_FSID\"
    monitors:
      - \"$CEPH_MON_IP:6789\"

secret:
  create: true
  name: csi-rbd-secret
  userID: k8s
  userKey: \"$CEPH_KEY\"

storageClass:
  create: true
  name: ceph-rbd
  clusterID: \"$CEPH_FSID\"
  pool: rbd
  reclaimPolicy: Delete
  allowVolumeExpansion: true
EOF

helm upgrade --install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
  -n ceph-csi-rbd \
  -f /tmp/csi-rbd-values.yaml

kubectl wait --for=condition=ready pod \
  -l app=ceph-csi-rbd \
  -n ceph-csi-rbd \
  --timeout=120s
"

echo "=============================="
echo " Step 5-3: ceph-csi-cephfs (File/RWX)"
echo "=============================="
CEPHFS_KEY=$($CSSH$C1_PUB "sudo ceph auth get-or-create client.k8s-fs mds 'allow rw' mon 'allow r' osd 'allow rw pool=cephfs_data' | grep key | awk '{print \$3}'")

$CSSH$M1_PUB "
cat <<EOF > /tmp/csi-cephfs-values.yaml
csiConfig:
  - clusterID: \"$CEPH_FSID\"
    monitors:
      - \"$CEPH_MON_IP:6789\"

secret:
  create: true
  name: csi-cephfs-secret
  adminID: k8s-fs
  adminKey: \"$CEPHFS_KEY\"

storageClass:
  create: true
  name: ceph-cephfs
  clusterID: \"$CEPH_FSID\"
  fsName: labfs
  reclaimPolicy: Delete
  allowVolumeExpansion: true
EOF

helm upgrade --install ceph-csi-cephfs ceph-csi/ceph-csi-cephfs \
  -n ceph-csi-cephfs \
  -f /tmp/csi-cephfs-values.yaml

kubectl wait --for=condition=ready pod \
  -l app=ceph-csi-cephfs \
  -n ceph-csi-cephfs \
  --timeout=120s
"

kubectl get storageclass

echo ""
echo "✅ Step 5 완료 - StorageClass: ceph-rbd, ceph-cephfs"
echo "   다음: scripts/06_csi_gpfs.sh"
```

---

## scripts/06_csi_gpfs.sh
```bash
#!/bin/bash
set -e
source scripts/.env

export KUBECONFIG=~/.kube/config-k8s-storage-lab
SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

GPFS_MOUNT="/gpfs/gpfs0"
GPFS_GUI_HOST="nsd-1"

echo "=============================="
echo " Step 6: Spectrum Scale GUI 활성화"
echo "=============================="
$CSSH$N1_PUB "
  sudo /usr/lpp/mmfs/gui/bin/initdb || true
  sudo systemctl enable --now gpfsgui || \
    sudo /usr/lpp/mmfs/gui/bin/guiserver start || true
  sleep 10
  sudo /usr/lpp/mmfs/bin/mmguiuser create \
    --username k8sadmin \
    --password Admin12345! \
    --role Administrator || true
"

echo "=============================="
echo " Step 6-1: Spectrum Scale CSI Helm 설치"
echo "=============================="
$CSSH$M1_PUB "
  helm repo add ibm-spectrum-scale \
    https://raw.githubusercontent.com/IBM/ibm-spectrum-scale-csi/master/stable/ibm-spectrum-scale-csi-operator
  helm repo update
  kubectl create namespace ibm-spectrum-scale-csi-driver || true
"

$CSSH$M1_PUB "
cat <<EOF > /tmp/scale-csi-values.yaml
primaryCluster:
  id: \"gpfslab\"
  primaryFs: \"gpfs0\"
  guiHost: \"$N1_PRIV\"
  guiPort: 443
  secret: scale-secret
  cacert: \"\"
  secureSslMode: false

clusters:
  - id: \"gpfslab\"
    secrets: \"scale-secret\"
    secureSslMode: false
    primary:
      primaryFs: \"gpfs0\"

nodeMapping:
  - k8sNode: \"master-1\"
    spectrumscaleNode: \"master-1\"
  - k8sNode: \"master-2\"
    spectrumscaleNode: \"master-2\"
  - k8sNode: \"master-3\"
    spectrumscaleNode: \"master-3\"
  - k8sNode: \"worker-1\"
    spectrumscaleNode: \"worker-1\"
  - k8sNode: \"worker-2\"
    spectrumscaleNode: \"worker-2\"
  - k8sNode: \"worker-3\"
    spectrumscaleNode: \"worker-3\"
EOF

kubectl create secret generic scale-secret \
  -n ibm-spectrum-scale-csi-driver \
  --from-literal=username=k8sadmin \
  --from-literal=password=Admin12345! \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install ibm-spectrum-scale-csi-operator \
  ibm-spectrum-scale/ibm-spectrum-scale-csi-operator \
  -n ibm-spectrum-scale-csi-driver \
  -f /tmp/scale-csi-values.yaml

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=ibm-spectrum-scale-csi-operator \
  -n ibm-spectrum-scale-csi-driver \
  --timeout=180s
"

echo "=============================="
echo " Step 6-2: GPFS StorageClass 생성"
echo "=============================="
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gpfs-scale
provisioner: spectrumscale.csi.ibm.com
parameters:
  volBackendFs: "gpfs0"
  clusterId:    "gpfslab"
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF

kubectl get storageclass

echo ""
echo "✅ Step 6 완료 - StorageClass: gpfs-scale"
echo "   다음: scripts/99_test_pvc.sh"
```

---

## scripts/99_test_pvc.sh
```bash
#!/bin/bash
set -e
export KUBECONFIG=~/.kube/config-k8s-storage-lab

echo "=============================="
echo " Test 1: ceph-rbd (Block RWO)"
echo "=============================="
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc-rbd
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ceph-rbd
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-rbd
spec:
  containers:
  - name: test
    image: busybox
    command: ["/bin/sh", "-c", "echo 'ceph-rbd OK' > /data/test.txt && cat /data/test.txt && sleep 60"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-pvc-rbd
  restartPolicy: Never
EOF

echo "=============================="
echo " Test 2: ceph-cephfs (File RWX)"
echo "=============================="
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc-cephfs
spec:
  accessModes: [ReadWriteMany]
  storageClassName: ceph-cephfs
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-cephfs
spec:
  containers:
  - name: test
    image: busybox
    command: ["/bin/sh", "-c", "echo 'cephfs OK' > /data/test.txt && cat /data/test.txt && sleep 60"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-pvc-cephfs
  restartPolicy: Never
EOF

echo "=============================="
echo " Test 3: gpfs-scale (GPFS)"
echo "=============================="
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc-gpfs
spec:
  accessModes: [ReadWriteMany]
  storageClassName: gpfs-scale
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-gpfs
spec:
  containers:
  - name: test
    image: busybox
    command: ["/bin/sh", "-c", "echo 'gpfs OK' > /data/test.txt && cat /data/test.txt && sleep 60"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-pvc-gpfs
  restartPolicy: Never
EOF

echo ""
echo "--- PVC 바인딩 대기 (최대 120초) ---"
for pvc in test-pvc-rbd test-pvc-cephfs test-pvc-gpfs; do
  echo -n "  $pvc: "
  kubectl wait pvc/$pvc --for=jsonpath='{.status.phase}'=Bound --timeout=120s \
    && echo "✅ Bound" || echo "❌ 실패"
done

echo ""
echo "--- Pod 상태 ---"
kubectl wait pod/test-pod-rbd    --for=condition=ready --timeout=120s || true
kubectl wait pod/test-pod-cephfs --for=condition=ready --timeout=120s || true
kubectl wait pod/test-pod-gpfs   --for=condition=ready --timeout=120s || true
kubectl get pods,pvc

echo ""
echo "--- 로그 확인 ---"
kubectl logs test-pod-rbd    || true
kubectl logs test-pod-cephfs || true
kubectl logs test-pod-gpfs   || true

echo ""
echo "=============================="
echo " 정리 명령어"
echo "=============================="
echo "  kubectl delete pod test-pod-rbd test-pod-cephfs test-pod-gpfs"
echo "  kubectl delete pvc test-pvc-rbd test-pvc-cephfs test-pvc-gpfs"
```

---

## start.sh
```bash
#!/bin/bash
set -e
export SSH_KEY_PATH="${SSH_KEY_PATH:-~/.ssh/id_rsa}"

echo "=============================="
echo " [1/4] AWS 인프라 생성"
echo "=============================="
cd opentofu/
tofu init
tofu apply -auto-approve
cd ..

echo "=============================="
echo " [2/4] 호스트 설정"
echo "=============================="
sleep 30
bash scripts/00_hosts_setup.sh

echo "=============================="
echo " [3/4] Ceph 클러스터 구성"
echo "=============================="
bash scripts/01_ceph_install.sh

echo "=============================="
echo " [4/4] 안내"
echo "=============================="
echo ""
echo "⚠️  GPFS는 IBM 패키지 수동 다운로드 후 진행 필요:"
echo "   1. ./gpfs-packages/ 에 .deb 파일 배치"
echo "   2. bash scripts/02_gpfs_install.sh"
echo "   3. bash scripts/03_nsd_setup.sh"
echo "   4. bash scripts/04_k8s_install.sh"
echo "   5. bash scripts/05_csi_ceph.sh"
echo "   6. bash scripts/06_csi_gpfs.sh"
echo "   7. bash scripts/99_test_pvc.sh"
echo ""
echo "✅ 인프라 및 Ceph 구성 완료!"
```

---

## stop.sh
```bash
#!/bin/bash
set -e
source scripts/.env 2>/dev/null || true

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
SNAPSHOT_MODE="${1:-snapshot}"

cd opentofu/

if [ "$SNAPSHOT_MODE" = "snapshot" ]; then
  echo "=============================="
  echo " EBS 스냅샷 생성"
  echo "=============================="
  aws ec2 describe-volumes \
    --region $AWS_REGION \
    --filters "Name=tag:Name,Values=*ceph-osd*" \
    --query 'Volumes[].VolumeId' \
    --output text | tr '\t' '\n' | while read vol_id; do
      echo "  스냅샷: $vol_id"
      aws ec2 create-snapshot \
        --region $AWS_REGION \
        --volume-id $vol_id \
        --description "k8s-storage-lab-backup-$(date +%Y%m%d)" \
        --query 'SnapshotId' --output text
  done

  echo "=============================="
  echo " EC2 중지"
  echo "=============================="
  aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "Name=tag:Name,Values=k8s-storage-lab-*" \
               "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text | tr '\t' '\n' | while read iid; do
      echo "  중지: $iid"
      aws ec2 stop-instances --region $AWS_REGION --instance-ids $iid
  done
  echo "✅ EC2 중지 완료"

elif [ "$SNAPSHOT_MODE" = "destroy" ]; then
  echo "⚠️  모든 리소스가 삭제됩니다. (yes/no)"
  read -r confirm
  if [ "$confirm" = "yes" ]; then
    tofu destroy -auto-approve
    echo "✅ 전체 삭제 완료"
  else
    echo "취소됨"
  fi
fi

cd ..
```