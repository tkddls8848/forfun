#/bin/bash
# allow ssh login with password
time=$(date "+%Y%m%d.%H%M%S")
# backup before overwriting
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config_$time.backup
sudo sed -i -e 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo systemctl restart sshd
