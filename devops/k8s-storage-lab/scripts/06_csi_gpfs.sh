#!/bin/bash
set -e
source scripts/.env

export KUBECONFIG=~/.kube/config-k8s-storage-lab
SSH_OPTS="-o StrictHostKeyChecking=no -i $SSH_KEY"
CSSH="ssh $SSH_OPTS ubuntu@"

WORKER_COUNT=${#WORKER_PUBS[@]}
GPFS_MOUNT="/gpfs/gpfs0"
GPFS_GUI_HOST="nsd-1"

NODE_MAPPING="  - k8sNode: \"master-1\"\n    spectrumscaleNode: \"master-1\""
for i in $(seq 1 $WORKER_COUNT); do
  NODE_MAPPING+="\n  - k8sNode: \"worker-$i\"\n    spectrumscaleNode: \"worker-$i\""
done

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
$(printf "$NODE_MAPPING")
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
