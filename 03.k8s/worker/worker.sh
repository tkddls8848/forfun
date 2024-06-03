sudo apt-get update -y
sudo timedatectl set-timezone Asia/Seoul
sudo apt-get install nfs-common -y

# connect nfs server folder to client server
mkdir /data
sudo mount -t nfs 192.168.56.100:/mnt/share /data

# config nfs directory for reboot nfs client server
sudo bash -c 'echo "192.168.56.100:/mnt/share /data nfs defaults 0 0" >> /etc/fstab'