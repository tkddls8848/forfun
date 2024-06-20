git clone --single-branch --branch release-1.11 https://github.com/rook/rook.git
cd ~/rook/deploy/examples
kubectl create -f crds.yaml -f common.yaml -f operator.yaml
kubectl create -f cluster.yaml -f toolbox.yaml -f filesystem.yaml
kubectl -n rook-ceph logs -l app=rook-ceph-operator -f
kubectl -n rook-ceph get pod
kubectl apply -f ~/rook/deploy/examples/csi/cephfs/storageclass.yaml
kubectl apply -f ~/rook/deploy/examples/csi/cephfs/kube-registry.yaml

sudo yum install -y epel-release
sudo yum install -y python-setuptools
sudo yum install -y ceph-deploy ceph-common
sudo ceph-deploy osd create k8s-worker1:/dev/sdb
sudo ceph-deploy osd create k8s-worker2:/dev/sdb
sudo ceph-deploy osd create k8s-worker3:/dev/sdb


curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add rook-release https://charts.rook.io/release
cd ~/rook/deploy/charts/rook-ceph
helm install --create-namespace --namespace rook-ceph rook-ceph rook-release/rook-ceph -f values.yaml
helm delete --namespace rook-ceph rook-ceph


#모든 노드
sudo yum install -y epel-release
sudo yum install -y ceph-deploy ceph-common ceph
