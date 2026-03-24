#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

swapoff -a
sed -i '/swap/d' /etc/fstab

apt-get update -y
apt-get install -y \
  curl wget vim jq \
  ksh perl \
  python3 python3-pip \
  libaio1t64 libssl-dev \
  net-tools iputils-ping \
  build-essential \
  linux-headers-$(uname -r)

apt-get install -y dkms

echo "NSD node bootstrap complete - GPFS install required manually"
