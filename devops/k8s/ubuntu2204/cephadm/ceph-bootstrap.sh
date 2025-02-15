#!/usr/bin/bash

## install Chrony 
sudo apt-get -y install chrony

## config DNS
sudo bash -c 'cat << EOF >> /etc/hosts
10.0.1.21  ceph1
10.0.1.22  ceph2
10.0.1.23  ceph3
EOF'

## install cephadm ceph-common
sudo apt-get install cephadm -y
sudo cephadm install ceph-common

#### run registry container
#sudo docker run --privileged -d --name registry -p 5001:5000 -v /var/lib/registry:/var/lib/registry --restart=always registry:2
#
### import container images for ceph
#sudo docker pull quay.io/ceph/ceph:v17
#sudo docker pull quay.io/prometheus/prometheus:v2.51.0
#sudo docker pull quay.io/prometheus/node-exporter:v1.7.0
#sudo docker pull quay.io/prometheus/alertmanager:v0.27.0
#sudo docker pull quay.io/ceph/grafana:10.4.0
#
### tag container images for ceph
#sudo docker tag quay.io/ceph/ceph:v17 $(hostname):5001/ceph:v17
#sudo docker tag quay.io/prometheus/node-exporter:v1.7.0 $(hostname):5001/node-exporter:v1.7.0
#
### push container images to registry container
#sudo docker push $(hostname):5001/ceph:v17
#sudo docker push $(hostname):5001/node-exporter:v1.7.0
#
### config ceph container images
#sudo bash -c 'cat << EOF >> initial-ceph.conf
#[mgr]
#mgr/cephadm/container_image_ceph = $(hostname):5001/ceph:v17
#mgr/cephadm/container_image_prometheus = $(hostname):5001/prometheus
#mgr/cephadm/container_image_node_exporter = $(hostname):5001/node-exporter:v1.7.0
#mgr/cephadm/container_image_grafana = $(hostname):5001/grafana
#mgr/cephadm/container_image_alertmanager = $(hostname):5001/alertmanager
#EOF'

## Running the bootstrap by local ceph image
#sudo cephadm bootstrap \
#        --mon-ip 10.0.1.21 \
#        --cluster-network 10.0.1.0/24 \
#        --ssh-user vagrant
#        --config initial-ceph.conf
sudo cephadm bootstrap --mon-ip 10.0.1.21 --cluster-network 10.0.1.0/24 --ssh-user vagrant

## copy ceph ssh public key to nodes
sudo apt-get install expect -y
for ((i=1; i<=3; i++))
do 
cat << EOF >> ceph${i}.sh
##!/usr/bin/expect -f
spawn ssh-copy-id -f -i /etc/ceph/ceph.pub vagrant@ceph$i
expect {
    "Are you sure you want to continue connecting (yes/no" {
        send "yes\r"; exp_continue
    }
    "password:" {
        send "vagrant\r"; exp_continue
    }
}
EOF
sudo chmod +x ceph${i}.sh
./ceph${i}.sh
sudo rm ceph${i}.sh
done

## add host
sudo ceph orch host add ceph2
sudo ceph orch host add ceph3

## host check
sudo ceph orch host ls

## apply mon, mgr, mds
sudo ceph orch apply mon --placement="ceph1,ceph2,ceph3"
sudo ceph orch apply mgr --placement="ceph2,ceph3"
#sudo ceph orch apply mds myfs --placement="ceph1,ceph2,ceph3"

## check disk device name
sudo fdisk -l

## attach osd to ceph cluster
for letter in {b..c}; do
    for num in {1..3}; do
        sudo ceph orch daemon add osd ceph$num:/dev/sd$letter
    done
done

## ceph status check 
sudo ceph -s

## vagrant user auth for docker
sudo usermod -aG docker $USER
newgrp docker
