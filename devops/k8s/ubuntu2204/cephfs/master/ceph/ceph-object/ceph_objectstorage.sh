#!/usr/bin/bash

# ceph objectstorage
cd ~/rook/deploy/examples/
kubectl create -f object.yaml ## "my-store" object store 생성
kubectl create -f object-user.yaml ## gateway 접근 권한 유저 생성

## gateway 접근 권한 유저 key 정보
access_key=$(kubectl -n rook-ceph get secret rook-ceph-object-user-my-store-my-user -o jsonpath='{.data.AccessKey}' | base64 --decode)
secret_key=$(kubectl -n rook-ceph get secret rook-ceph-object-user-my-store-my-user -o jsonpath='{.data.SecretKey}' | base64 --decode)
echo $access_key
echo $secret_key

## install gateway S3 API AWS-CLI
sudo apt-get install -y awscli
aws configure

## make bucket, copy file, listing file in my-test-bucket
aws --endpoint-url=http://10.233.21.192:80/ s3 mb s3://my-test-bucket
aws --endpoint-url=http://10.233.21.192:80/ s3 cp myfile.txt s3://my-test-bucket
aws --endpoint-url=http://10.233.21.192:80/ s3 ls s3://my-test-bucket
