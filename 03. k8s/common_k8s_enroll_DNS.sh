# entitle hostname 
tee /etc/hosts <<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
:1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF

# add cluster nodes in the hosts file $1 is worker_node number from vagrantfile
echo "192.168.55.10 master  m" >> /etc/hosts
for ((i = 1; i <= $1; i++)) do
    echo "192.168.55.1$i worker$i w$i" >> /etc/hosts
done