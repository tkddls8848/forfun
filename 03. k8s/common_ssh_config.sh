#/bin/bash
# allow ssh login with password
time=$(date "+%Y%m%d.%H%M%S")
# backup before overwriting
cp /etc/ssh/sshd_config /etc/ssh/sshd_config_$time.backup
sed -i -e 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
systemctl restart sshd
