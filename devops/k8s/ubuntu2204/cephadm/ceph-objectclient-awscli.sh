#!/usr/bin/bash

## create object gateway server
sudo ceph orch apply rgw object

## create object gateway user
sudo apt-get install -y jq
sudo radosgw-admin user create --uid="exampleuser" --display-name="Example User" | jq -r '.keys[0]' > userdata.json

## install awscli
sudo apt install -y awscli

## configure awscli user
ACCESS_KEY=$(cat userdata.json | jq -r '.access_key')
SECRET_KEY=$(cat userdata.json | jq -r '.secret_key')
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

## create bucket
aws --endpoint-url http://ceph2 s3 mb s3://my-bucket

## upload file to S3 bucket
aws --endpoint-url http://ceph2 s3 cp userdata.json s3://my-bucket

## download file to S3 bucket
rm userdata.json
aws --endpoint-url http://ceph2 s3 cp s3://my-bucket/userdata.json .

## list file in S3 bucket
aws --endpoint-url http://ceph2 s3 ls s3://my-bucket

## delete file in S3 bucket
aws --endpoint-url http://ceph2 s3 rm s3://my-bucket/userdata.json

## delete S3 bucket
aws --endpoint-url http://ceph2 s3 rb s3://my-bucket
