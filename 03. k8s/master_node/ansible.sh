#!/usr/bin/bash

# establish ssh key connection
sudo ssh-keygen -t rsa
sudo ssh-copy-id 192.168.1.10
sudo ssh-copy-id 192.168.1.21
sudo ssh-copy-id 192.168.1.22
sudo ssh-copy-id 192.168.1.100

# install python 3.10 for centos7 that default version 2.7
git clone -b v2.24.0 https://github.com/kubernetes-sigs/kubespray.git
tar -xzf Python-3.10.2.tgz
cd Python-3.10.2
sudo ./configure --enable-optimizations

# set python alias for change default python
PYTHON=$(which python3.10)
PIP=$(which pip3.10)
sudo echo 'alias python='$PYTHON >> ~/.bashrc
sudo echo 'alias pip='$PIP >> ~/.bashrc
source ~/.bashrc
user=$(whoami)
sudo chown $user /etc/bashrc
sudo echo 'alias python='$PYTHON >> /etc/bashrc
sudo echo 'alias pip='$PIP >> /etc/bashrc
source /etc/bashrc

cd kubespray
sudo yum install -y openssl-devel bzip2-devel libffi-devel
python -m pip install requirements.txt
