#!/usr/bin/bash
#run script in ubuntu OS

# swapoff -a to disable swapping
sudo swapoff -a
sudo sed -e '/swap/s/^/#/' -i /etc/fstab

## install microk8s
sudo snap install microk8s --classic --channel=1.30/stable

## add user group for use microk8s
mkdir -p ~/.kube
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube

## install addons
#microk8s status --wait-ready 
sudo microk8s enable dns hostpath-storage metallb:10.64.140.43-10.64.140.49 rbac

## install nvidia operator helm chart
#show error by install microk8s enable nvidia (search for why in future)
#symlink issue: symlink.txt
sudo microk8s helm repo add nvidia https://helm.ngc.nvidia.com/nvidia \
    && sudo microk8s helm repo update

sudo microk8s helm install gpu-operator nvidia/gpu-operator --namespace gpu-operator-resources --create-namespace \
    --set devicePlugin.enabled=true \
    --set toolkit.enabled=true  \
    --set driver.enabled=true

# configuring microk8s containerd runtime toml file
sudo bash -c 'cat << EOF >> /var/snap/microk8s/current/args/containerd-template.toml
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
        privileged_without_host_devices = false
        runtime_engine = ""
        runtime_root = ""
        runtime_type = "io.containerd.runc.v2"

        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
          BinaryName = "/usr/local/nvidia/toolkit/nvidia-container-runtime"

      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia-experimental]
        privileged_without_host_devices = false
        runtime_engine = ""
        runtime_root = ""
        runtime_type = "io.containerd.runc.v2"

        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia-experimental.options]
          BinaryName = "/usr/local/nvidia/toolkit/nvidia-container-runtime-experimental"
EOF'
sudo microk8s stop
sudo microk8s start

## session restart
newgrp microk8s ## restart session required

## Verify installation
# expect return: all validations are successful
sudo microk8s kubectl logs -n gpu-operator-resources -lapp=nvidia-operator-validator -c nvidia-operator-validator




