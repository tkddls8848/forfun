#!/usr/bin/bash

### install openssl 1.1.1 => install python 3.10 => install kubespray ansible by pip 3.10 (alias pip)

########### 1. install openssl 1.1.1 ###########
# repo update
sudo yum -y update
# remove openssl 1.0.1k
sudo yum -y remove openssl openssl-devel

# install packages for openssl 1.1.1
sudo yum install -y gcc gcc-c++ pcre-devel zlib-devel perl wget libffi-devel bzip2-devel git

# download and install openssl 1.1.1
cd /usr/local/src
sudo chown $(whoami):$(whoami) /usr/local/src
wget https://www.openssl.org/source/openssl-1.1.1k.tar.gz
tar xvfz openssl-1.1.1k.tar.gz
cd openssl-1.1.1k
./config --prefix=/usr/local/ssl --openssldir=/usr/local/ssl shared zlib
make
sudo make install

# make config file for openssl 1.1.1
sudo touch /etc/ld.so.conf.d/openssl-1.1.1k.conf
sudo chown $(whoami):$(whoami) /etc/ld.so.conf.d/openssl-1.1.1k.conf
sudo echo '/usr/local/ssl/lib' >> /etc/ld.so.conf.d/openssl-1.1.1k.conf

# symbol link to lib64
sudo ln -s /usr/local/ssl/lib/libssl.so.1.1 /usr/lib64/libssl.so.1.1
sudo ln -s /usr/local/ssl/lib/libcrypto.so.1.1 /usr/lib64/libcrypto.so.1.1
sudo ln -s /usr/local/ssl/bin/openssl /bin/openssl

########### 2. install python by pyenv in root user ###########
cd /opt
sudo wget https://www.python.org/ftp/python/3.11.3/Python-3.11.3.tgz  --no-check-certificate
sudo tar -zxvf Python-3.11.3.tgz
cd Python-3.11.3
./configure
make
sudo make install
sudo chown $(whoami):$(whoami) /etc/profile
echo 'alias python=/usr/local/bin/python3.11' >> /etc/profile
echo 'alias pip=/usr/local/bin/pip3.11' >> /etc/profile
source /etc/profile
pip3 install --upgrade pip

########### 3. install kubespray ansible by pip ###########
cd ~
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
pip3 install -r requirements.txt



