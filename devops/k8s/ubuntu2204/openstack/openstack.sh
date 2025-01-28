#!/usr/bin/bash

## https://gam1532.tistory.com/30
## add stack user
sudo adduser --disabled-password stack
echo "stack:stack" | sudo chpasswd
sudo su -
echo "stack ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
sudo su stack
## clone devstack
cd ~/
sudo apt-get install git
git clone https://git.openstack.org/openstack-dev/devstack
cd ~/devstack
## config local ip info in local.conf
sudo cp ./samples/local.conf ./
sed -i "s/#HOST_IP=w.x.y.z/HOST_IP=\$(hostname -I | awk '{print \$2}')/" ./local.conf
## exec install openstack script
./stack.sh