#!/usr/bin/bash
#run script in ubuntu OS

# blacklist nouveau
sudo bash -c "echo blacklist nouveau > /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
sudo bash -c "echo options nouveau modeset=0 >> /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
sudo bash -c "echo blacklist nouveau > /etc/modprobe.d/blacklist-nouveau.conf"
sudo bash -c "echo options nouveau modeset=0 >> /etc/modprobe.d/blacklist-nouveau.conf"
sudo update-initramfs -u
sudo reboot

# Installing containerd
sudo apt update
sudo apt install containerd -y

sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

# remove installed old CUDA
sudo apt-get --purge -y remove 'cuda*'
sudo apt-get --purge -y remove 'nvidia*'
sudo apt-get autoremove --purge cuda
cd /usr/local/
sudo rm -rf cuda*

# Installing nvidia CUDA with Apt
sudo apt update
sudo ubuntu-drivers autoinstall
sudo apt-get update
sudo apt-get -y install cuda-toolkit-12-4
sudo apt-get install -y nvidia-container-toolkit

# Installing nvidia driver
sudo ubuntu-drivers autoinstall -y

# Installing nvidia-cuda-toolkit
sudo apt-get install nvidia-cuda-toolkit -y

# Installing nvidia-container-toolkit
sudo apt-get install curl -y
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update -y
sudo apt-get install -y nvidia-container-toolkit -y


# containerd/config.toml 변경
# https://velog.io/@myeong01/Containerd-%EB%A1%9C-GPU-Kubernetes-%ED%81%B4%EB%9F%AC%EC%8A%A4%ED%84%B0-%EA%B5%AC%EC%B6%95%ED%95%98%EA%B8%B0
sudo sed -i '/\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes\]/a \
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]\
          privileged_without_host_devices = false\
          runtime_engine = ""\
          runtime_root = ""\
          runtime_type = "io.containerd.runc.v1"\
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]\
            BinaryName = "/usr/bin/nvidia-container-runtime"\
            SystemdCgroup = true' /etc/containerd/config.toml

sudo sed -i -e 's/default_runtime_name = "runc"/default_runtime_name = "nvidia"/g' /etc/containerd/config.toml

sudo systemctl restart containerd










