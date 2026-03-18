#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

swapoff -a
sed -i '/swap/d' /etc/fstab

apt-get update -y
apt-get install -y \
  curl wget vim jq \
  python3 python3-pip \
  lvm2 \
  net-tools iputils-ping \
  chrony

systemctl enable --now chrony

apt-get install -y docker.io || true
systemctl enable --now docker || true

echo "Ceph node bootstrap complete - cephadm install in 01_ceph_install.sh"
