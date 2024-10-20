#!/usr/bin/bash
#run script in ubuntu OS
wget https://github.com/containerd/containerd/releases/download/v1.6.28/containerd-1.6.28-linux-amd64.tar.gz
tar xvf containerd-1.6.28-linux-amd64.tar.gz
# blacklist nouveau
sudo bash -c "echo blacklist nouveau > /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
sudo bash -c "echo options nouveau modeset=0 >> /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
sudo bash -c "echo blacklist nouveau > /etc/modprobe.d/blacklist-nouveau.conf"
sudo bash -c "echo options nouveau modeset=0 >> /etc/modprobe.d/blacklist-nouveau.conf"
sudo update-initramfs -u
sudo reboot

# remove installed old nvidia-driver
sudo apt-get --purge -y remove 'nvidia*'

# Installing nvidia driver
sudo ubuntu-drivers autoinstall

sudo apt-get update
sudo apt-get install nvidia-headless-550 nvidia-utils-550

# Installing nvidia-container-toolkit to host
sudo apt-get install curl -y
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update -y
sudo apt-get install nvidia-container-toolkit -y

# Installing nvidia-container-runtime to host
curl -s -L https://nvidia.github.io/nvidia-container-runtime/gpgkey | \
  sudo apt-key add -
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-container-runtime/$distribution/nvidia-container-runtime.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-runtime.list
sudo apt-get update
sudo apt-get install nvidia-container-runtime

#labels??
Labels:            
nvidia.com/gpu.deploy.container-toolkit=true
microk8s kubectl label nodes ubuntu nvidia.com/gpu.deploy.container-toolkit=true

microk8s kubectl label nodes ubuntu nvidia.com/gpu.present=true


















