#!/usr/bin/bash

# Running the bootstrap command
sudo cephadm bootstrap --mon-ip 10.0.1.11 --cluster-network 10.0.1.0/24 --ssh-user vagrant

# copy ceph ssh public key to nodes
sudo apt-get install expect -y
for ((i=1; i<=3; i++))
do 
cat << EOF >> ceph${i}.sh
#!/usr/bin/expect -f
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

# add host
sudo ceph orch host add ceph2
sudo ceph orch host add ceph3

# host check
sudo ceph orch host ls

# apply mon, mgr, mds
sudo ceph orch apply mon --placement="ceph1,ceph2,ceph3"
sudo ceph orch apply mgr --placement="ceph1,ceph2,ceph3"
sudo ceph orch apply mds myfs --placement="ceph1,ceph2,ceph3"

# check disk device name
sudo fdisk -l

# attach osd to ceph cluster
for letter in {b..d}; do
    for num in {1..3}; do
        sudo ceph orch daemon add osd ceph$num:/dev/sd$letter
    done
done

# ceph status check 
sudo ceph -s

