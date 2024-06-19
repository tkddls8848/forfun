git clone --single-branch --branch release-1.11 https://github.com/rook/rook.git
cd rook/deploy/examples
kubectl create -f crds.yaml -f common.yaml -f operator.yaml
kubectl -n rook-ceph get pod
kubectl create -f cluster.yaml
kubectl -n rook-ceph logs -l app=rook-ceph-operator -f
kubectl -n rook-ceph get pod
kubectl create -f toolbox.yaml


#모든 노드
sudo yum install -y epel-release
sudo yum install -y ceph-deploy ceph-common ceph

sudo yum install -y https://download.ceph.com/rpm-mimic/el7/x86_64/librados2-13.2.4-0.el7.x86_64.rpm
sudo yum install -y http://download.ceph.com/rpm-mimic/el7/x86_64/libradosstriper1-13.2.4-0.el7.x86_64.rpm
sudo yum install -y http://download.ceph.com/rpm-mimic/el7/x86_64/python-rados-13.2.4-0.el7.x86_64.rpm
sudo yum install -y http://download.ceph.com/rpm-mimic/el7/x86_64/libcephfs2-13.2.4-0.el7.x86_64.rpm
sudo yum install -y http://download.ceph.com/rpm-mimic/el7/x86_64/python-cephfs-13.2.4-0.el7.x86_64.rpm
sudo yum install -y http://download.ceph.com/rpm-mimic/el7/x86_64/librbd1-13.2.4-0.el7.x86_64.rpm
sudo yum install -y http://download.ceph.com/rpm-mimic/el7/x86_64/python-rbd-13.2.4-0.el7.x86_64.rpm
sudo yum install -y http://download.ceph.com/rpm-mimic/el7/x86_64/librgw2-13.2.4-0.el7.x86_64.rpm
sudo yum install -y http://download.ceph.com/rpm-mimic/el7/x86_64/python-rgw-13.2.4-0.el7.x86_64.rpm
sudo yum install -y https://download.ceph.com/rpm-mimic/el7/x86_64/ceph-common-13.2.4-0.el7.x86_64.rpm
sudo yum install -y http://download.ceph.com/rpm-mimic/el7/x86_64/ceph-base-13.2.4-0.el7.x86_64.rpm http://download.ceph.com/rpm-mimic/el7/x86_64/ceph-selinux-13.2.4-0.el7.x86_64.rpm
sudo yum install -y https://download.ceph.com/rpm-mimic/el7/x86_64/ceph-mds-13.2.4-0.el7.x86_64.rpm
sudo yum install -y https://download.ceph.com/rpm-mimic/el7/x86_64/ceph-mon-13.2.4-0.el7.x86_64.rpm
sudo yum install -y https://download.ceph.com/rpm-mimic/el7/x86_64/ceph-mgr-13.2.4-0.el7.x86_64.rpm
sudo yum install -y https://download.ceph.com/rpm-mimic/el7/x86_64/ceph-osd-13.2.4-0.el7.x86_64.rpm
sudo yum install -y https://download.ceph.com/rpm-mimic/el7/x86_64/ceph-13.2.4-0.el7.x86_64.rpm
sudo yum install http://download.ceph.com/rpm-mimic/el7/x86_64/ceph-radosgw-13.2.4-0.el7.x86_64.rpm

#마스터 노드만
cd ~
sudo mkdir my-cluster
cd my-cluster
sudo ceph-deploy new k8s-master
sudo bash -c 'cat << EOF >> ceph.conf
public_network = 10.233.64.0/18
EOF'
sudo ceph-deploy install k8s-master
sudo ceph-deploy mon create-initial
sudo ceph-deploy admin k8s-master
sudo ceph-deploy mgr create k8s-master


sudo ceph auth get-or-create-key client.bootstrap-osd mon 'allow profile bootstrap-osd' -o /var/lib/ceph/bootstrap-osd/ceph.keyring

#마스터 노드만
sudo ceph-deploy osd create k8s-worker1:/dev/sdb
sudo ceph-deploy osd create k8s-worker2:/dev/sdb
sudo ceph-deploy osd create k8s-worker3:/dev/sdb




git clone https://github.com/ceph/ceph-csi.git
cd ceph-csi

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

helm repo add ceph-csi https://ceph.github.io/csi-charts
helm search repo ceph-csi
kubectl create namespace "ceph-fs"

sudo bash -c 'cat << EOF >> values.yaml
csiConfig: - clusterID: "test-cephfs" monitors: - "192.168.0.138:6789" - "192.168.0.138:6789" - "192.168.0.141:6789" secret: create: true name: "ceph-fs-secret" adminID: "admin" adminKey: "AQD81LRjujj5ERAASy7HgGX92yusPCYDiJIOjg==" storageClass: create: true name: ceph-fs-sc annotations: storageclass.beta.kubernetes.io/is-default-class: "true" storageclass.kubesphere.io/supported-access-modes: '["ReadWriteOnce","ReadOnlyMany","ReadWriteMany"]' clusterID: "test-cephfs" fsName: "chunvol1" pool: "cephfs.chunvol1.data" provisionerSecret: ceph-fs-secret provisionerSecretNamespace: ceph-fs controllerExpandSecret: ceph-fs-secret controllerExpandSecretNamespace: ceph-fs nodeStageSecret: ceph-fs-secret nodeStageSecretNamespace: ceph-fs reclaimPolicy: Delete allowVolumeExpansion: true mountOptions: - discard
'

helm install --namespace "ceph-fs" "ceph-fs-sc" ceph-csi/ceph-csi-cephfs -f values.yaml
helm status "ceph-fs-sc" -n "ceph-fs"

sudo bash -c 'cat << EOF > ceph_pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
    name: ceph-pvc
spec:
    accessModes:
    - ReadWriteOnce
    resources:
        requests:
            storage: 10Gi
    storageClassName: rook-cephfs
EOF'
kubectl apply -f ceph_pvc.yaml


sudo bash -c 'cat << EOF > pod.yaml
apiVersion: v1
kind: Pod
metadata:
    name: nginx-pod
spec:
    containers:
    - name: nginx
      image: nginx
      ports:
      - containerPort: 80
      volumeMounts:
        - mountPath: /usr/share/nginx/html
          name: ceph-storage
    volumes:
    - name: ceph-storage
      persistentVolumeClaim:
        claimName: ceph-pvc
EOF'

kubectl apply -f pod.yaml

