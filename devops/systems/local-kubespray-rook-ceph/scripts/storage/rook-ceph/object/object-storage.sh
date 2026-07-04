#!/usr/bin/env bash
set -euo pipefail

## ceph objectstorage
ROOK_HOME="${ROOK_HOME:-$HOME/rook}"
WORKDIR="${WORKDIR:-$HOME/k8s-install-manifests}"
cd "$ROOK_HOME/deploy/examples"
kubectl apply -f object.yaml # "my-store" object store 생성
kubectl apply -f object-user.yaml # gateway 접근 권한 유저 생성
kubectl -n rook-ceph wait --for=condition=Ready cephobjectstore/my-store --timeout=10m

if [[ "${RUN_SMOKE_TEST:-false}" != "true" ]]; then
  exit 0
fi

## gateway 접근 권한 유저 key 정보
ACCESS_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-my-store-my-user -o jsonpath='{.data.AccessKey}' | base64 --decode)
SECRET_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-my-store-my-user -o jsonpath='{.data.SecretKey}' | base64 --decode)

## install gateway S3 API AWS-CLI
sudo apt-get install -y awscli

## configure awscli user non-interactively
aws configure set aws_access_key_id "$ACCESS_KEY"
aws configure set aws_secret_access_key "$SECRET_KEY"
aws configure set region us-east-1
aws configure set output json

## make bucket, copy file, listing file in my-test-bucket
endpoint_ip=$(kubectl -n rook-ceph get svc rook-ceph-rgw-my-store -o jsonpath='{.spec.clusterIP}')
endpoint_port=$(kubectl -n rook-ceph get svc rook-ceph-rgw-my-store -o jsonpath='{.spec.ports[0].port}')
install -m 0755 -d "$WORKDIR"
echo "rook object storage smoke test" > "$WORKDIR/myfile.txt"
aws --endpoint-url="http://$endpoint_ip:$endpoint_port/" s3 mb s3://my-test-bucket || true
aws --endpoint-url="http://$endpoint_ip:$endpoint_port/" s3 cp "$WORKDIR/myfile.txt" s3://my-test-bucket
aws --endpoint-url="http://$endpoint_ip:$endpoint_port/" s3 ls s3://my-test-bucket
