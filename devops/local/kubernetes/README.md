# Local Kubernetes Labs

Lab-only Kubernetes cluster definitions.

Path convention:

```text
kubernetes/<provider>/<os>/<installer>/<profile>
```

## Clusters

| Path | Purpose | Provider | Network | Inventory | Notes |
| --- | --- | --- | --- | --- | --- |
| `vagrant/ubuntu/kubeadm/basic` | kubeadm Kubernetes cluster | VirtualBox | `192.168.56.0/24`, pods `10.244.0.0/16` | `inventory/inventory.ini` | Flannel, non-HA |
| `vagrant/ubuntu/kubespray/rook-ceph` | Kubespray + Rook/Ceph lab | VirtualBox | `192.168.56.0/24`, pods `10.244.0.0/16` | `inventory/inventory.ini` | Flannel, non-HA |
| `kvm/ubuntu/kubeadm/gpu` | GPU kubeadm lab | libvirt/KVM + host GPU worker | libvirt NAT | none | SSH-based flow |
| `vagrant/centos8/minikube/kubevirt` | Minikube/KubeVirt lab | VirtualBox/KVM2 | local | none | CentOS 8 is legacy/EOL |
| `vagrant/rocky/minikube/kubevirt` | Rocky Minikube/KubeVirt lab | VirtualBox/KVM2 | local | none | pinned Minikube/KubeVirt |
| `host/ubuntu/microk8s/kubeflow-gpu` | MicroK8s + Kubeflow GPU lab | host snap | host-defined | none | MicroK8s default CNI |
| `host/ubuntu/k3s/ai` | K3s AI lab | host | host-defined | none | K3s version is pinned |

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

Run repository checks from `devops/local/kubernetes`:

```powershell
./validate.ps1
```

## Assumptions

These definitions are lab-only and non-HA unless explicitly stated otherwise. They are not hardened production clusters.
Generated local state such as `.vagrant/`, VM disks, kubeconfig files, join commands, and temporary Ansible/Kubespray checkouts must not be committed.
