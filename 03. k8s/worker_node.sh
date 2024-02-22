#!/usr/bin/bash

# worker node config
sudo kubeadm join 192.168.1.10:6443 \
        --token 123456.1234567890123456 \
        --discovery-token-unsafe-skip-ca-verification