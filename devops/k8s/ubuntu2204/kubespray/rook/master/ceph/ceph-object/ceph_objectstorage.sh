#!/usr/bin/bash

# ceph objectstorage
cd ~/rook/deploy/examples/
kubectl create -f object.yaml ## "my-store" object store 생성
kubectl create -f object-user.yaml ## gateway 접근 권한 유저 생성

## gateway 접근 권한 유저 key 정보
ACCESS_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-my-store-my-user -o jsonpath='{.data.AccessKey}' | base64 --decode)
SECRET_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-my-store-my-user -o jsonpath='{.data.SecretKey}' | base64 --decode)

## install gateway S3 API AWS-CLI
sudo apt-get install -y awscli

# configure awscli user
cat << EOF >> aws.sh
#!/usr/bin/expect -f
spawn aws configure
expect {
    "AWS Access Key ID" {
        send "$ACCESS_KEY\r"; exp_continue
    }
    "AWS Secret Access Key" {
        send "$SECRET_KEY\r"; exp_continue
    }
    "Default region name" {
        send "\r"; exp_continue
    }
    "Default output format" {
        send "\r"; exp_continue
    }
}
EOF
sudo chmod +x aws.sh
./aws.sh
sudo rm aws.sh

## make bucket, copy file, listing file in my-test-bucket
endpoint_ip=$(kubectl -n rook-ceph get svc rook-ceph-rgw-my-store -o jsonpath='{.spec.clusterIP}')
endpoint_port=$(kubectl -n rook-ceph get svc rook-ceph-rgw-my-store -o jsonpath='{.spec.ports[0].port}')
aws --endpoint-url=http://$endpoint_ip:$endpoint_port/ s3 mb s3://my-test-bucket
aws --endpoint-url=http://$endpoint_ip:$endpoint_port/ s3 cp myfile.txt s3://my-test-bucket
aws --endpoint-url=http://$endpoint_ip:$endpoint_port/ s3 ls s3://my-test-bucket

