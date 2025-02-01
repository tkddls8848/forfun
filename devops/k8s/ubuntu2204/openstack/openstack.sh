#!/usr/bin/bash

## add stack user
sudo useradd -s /bin/bash -d /opt/stack -m stack
sudo chmod +x /opt/stack
echo "stack ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/stack
sudo -u stack -i

## clone devstack git repo
cd ~/
sudo apt-get install git
git clone https://git.openstack.org/openstack-dev/devstack
cd ~/devstack

## config info in local.conf
sudo cp ./samples/local.conf ./
sed -i "s/#HOST_IP=w.x.y.z/HOST_IP=\$(hostname -I | awk '{print \$2}')/" ./local.conf
sed -i "s/ADMIN_PASSWORD=nomoresecret/ADMIN_PASSWORD=admin/" ./local.conf

## exec install openstack script
./stack.sh