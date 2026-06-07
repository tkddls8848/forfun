# Kubernetes Lab Definitions

This directory contains lab-only Kubernetes and storage cluster definitions.

## Clusters

| Path | Purpose | Provider | Network | Inventory | Notes |
| --- | --- | --- | --- | --- | --- |
| `ubuntu/kubeadm` | kubeadm Kubernetes cluster | VirtualBox | `192.168.56.0/24`, pods `10.244.0.0/16` | `ubuntu/kubeadm/inventory.ini` | Flannel, non-HA |
| `ubuntu/kubespray` | Kubespray Kubernetes cluster | VirtualBox | `192.168.56.0/24`, pods `10.244.0.0/16` | `ubuntu/kubespray/inventory.ini` | Flannel, non-HA |
| `centos8/cephfs` | CentOS 8 Kubespray + Rook/Ceph lab | VirtualBox | `192.168.1.0/24`, pods `10.244.0.0/16` | `centos8/cephfs/inventory.ini` | CentOS 8 is legacy/EOL |
| `ubuntu/cephadm` | Cephadm storage lab | VirtualBox | public `192.168.60.0/24`, cluster `192.168.61.0/24` | `ubuntu/cephadm/inventory.ini` | non-HA single monitor |
| `kvm/cephadm` | Cephadm storage lab | libvirt/KVM | public `192.168.60.0/24`, cluster `192.168.61.0/24` | `kvm/cephadm/inventory.ini` | non-HA single monitor |
| `kvm/kubeadm_GPU` | GPU kubeadm lab | libvirt/KVM | libvirt NAT | none | Exception: keeps SSH-based flow |
| `centos8/minikube` | Minikube/KubeVirt lab | VirtualBox/KVM2 | local | none | pinned Minikube/KubeVirt |
| `rocky/minikube` | Rocky Minikube/KubeVirt lab | VirtualBox/KVM2 | local | none | pinned Minikube/KubeVirt |
| `ubuntu/microk8s/kubeflow_gpu` | MicroK8s + Kubeflow GPU lab | host snap | host-defined | none | MicroK8s default CNI |
| `ubuntu/k3s` | K3s AI lab | host | host-defined | none | K3s version is pinned |

## Host Tools

- Vagrant
- VirtualBox or libvirt/KVM depending on the cluster
- PowerShell for `validate.ps1` on Windows hosts
- Optional: `shellcheck`, `ansible-inventory`, `ansible-playbook`

## Common Commands

Run from the cluster directory:

```bash
vagrant up
vagrant destroy -f
```

Run repository checks from `devops/k8s`:

```powershell
./validate.ps1
```

## Assumptions

These definitions are lab-only and non-HA unless explicitly stated otherwise. They are not hardened production clusters.
Generated local state such as `.vagrant/`, VM disks, kubeconfig files, join commands, and temporary Ansible/Kubespray checkouts must not be committed.
