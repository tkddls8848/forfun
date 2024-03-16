#!/usr/bin/bash

# install NFS server
sudo yum install -y nfs nfs-utils cifs-utils rpc-bind

# make share folder
sudo mkdir -p /nfs

# install packages for util
sudo yum install -y yum-utils vim

# enroll share folder
sudo bash -c 'cat << EOF > /etc/exports
/nfs *(rw,sync,no_subtree_check,no_root_squash)
EOF'
sudo systemctl restart nfs-server
