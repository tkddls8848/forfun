# CentOS 8 Minikube + KubeVirt lab

## Purpose and provider

This historical lab creates one CentOS Linux 8 guest with Vagrant and VirtualBox, then starts a second-level Minikube VM with Minikube's built-in `kvm2` driver. KubeVirt runs on the Minikube cluster and starts a small CirrOS test VM. The definitions remain separate from the Rocky variant so the lifecycle and repository differences are visible.

## CentOS 8 support warning

CentOS Linux 8 reached end of life on 2021-12-31. The `generic/centos8` box still points at retired public mirror metadata, so the `dnf update` in `Vagrantfile` and later package installs are not a supported, reproducible fresh-install path. This repository deliberately does not add a Vault mirror compatibility shim. Use the Rocky variant for a runnable lab. This definition can only proceed when an operator has already supplied a trusted archived or internal CentOS 8 repository, and it receives no security updates.

The Minikube/Kubernetes/KubeVirt pins themselves are compatible; the unachievable part on a stock CentOS 8 box is the EOL OS package bootstrap.

## Prerequisites

- An x86_64 host with hardware virtualization and nested virtualization enabled.
- Vagrant and VirtualBox, with at least 16 GiB RAM and four CPUs available to the guest.
- VirtualBox host-only networking configured to allow `192.168.81.0/24`; newer VirtualBox releases otherwise reject the configured `192.168.81.10` address.
- Internet access to Google Storage, GitHub, `registry.k8s.io`, and Quay.
- For this EOL definition only, a trusted CentOS 8 package mirror configured before `dnf update` runs.

Minikube's KVM driver requires libvirt 1.3.1+ and qemu-kvm 2.0+. CentOS 8 packages meet those minimums when they are obtainable. The scripts fail early when nested KVM or the required group membership is unavailable.

## Pinned versions

| Component | Pin |
| --- | --- |
| Minikube | `v1.38.1` (`minikube-linux-amd64` SHA-256 verified) |
| Kubernetes | `v1.35.1` |
| KubeVirt and `virtctl` | `v1.8.2` (release SHA-256 values verified) |
| Minikube driver/runtime | built-in `kvm2` / `containerd` |
| Test disk | `quay.io/kubevirt/cirros-container-disk-demo@sha256:ebdb8d8b9b480f6ee7664ed3fdde8428767664f507d98f94090edeff04d7ebf2` |

Minikube v1.38.1 added and defaults to Kubernetes v1.35.1. The KubeVirt support matrix lists KubeVirt 1.8 as supported on Kubernetes 1.35 and 1.34, so the explicit Kubernetes pin is within both projects' supported pair. See the [Minikube v1.38.1 release](https://github.com/kubernetes/minikube/releases/tag/v1.38.1), [KubeVirt support matrix](https://github.com/kubevirt/sig-release/blob/main/releases/k8s-support-matrix.md), and [Minikube kvm2 requirements](https://minikube.sigs.k8s.io/docs/drivers/kvm2/).

The operator and custom-resource manifests are vendored from the KubeVirt v1.8.2 GitHub release under `manifests/kubevirt/`. `kubevirt_run.sh` verifies their official release SHA-256 values and applies only local files. `test-vm.yaml` is a local equivalent of the former KubeVirt labs VM manifest with its container image pinned by digest.

## Exact step order

These commands only work after the CentOS 8 repository warning above has been addressed outside this definition.

1. From this directory, create and provision the outer VM: `vagrant up`.
2. Enter it: `vagrant ssh`.
3. Run the pre-reboot virtualization phase: `bash /vagrant/scripts/addons/kubevirt/kubevirt_install.sh`.
4. Reboot at the explicit boundary: `sudo reboot`. The SSH session will close.
5. Re-enter the guest: `vagrant ssh`.
6. Validate KVM and start the pinned cluster: `bash /vagrant/scripts/addons/kubevirt/kubevirt_start.sh`.
7. Install KubeVirt from local manifests and exercise the test VM: `bash /vagrant/scripts/addons/kubevirt/kubevirt_run.sh`.

The install script never invokes `newgrp` or reboots itself. The post-reboot script checks that the new `libvirt` and `kvm` memberships are active before starting Minikube.

## How this differs from the Rocky variant

| Area | CentOS 8 definition | Rocky definition |
| --- | --- | --- |
| Vagrant box | `generic/centos8` | `generic/rocky8` |
| OS lifecycle | EOL since 2021-12-31; no supported public package bootstrap | Supported Rocky 8 lifecycle; viable fresh provisioning |
| Package source | Retired CentOS mirror metadata unless an operator supplies an archive/internal mirror | Active Rocky repositories; Docker uses Docker's RHEL-compatible CentOS repository |
| Intended use | Historical/reference definition | Runnable lab and recommended variant |

The Minikube, Kubernetes, KubeVirt, local manifests, resource sizing, network, and numbered reboot flow intentionally remain the same so only the OS-specific behavior differs.
