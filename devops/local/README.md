# Local DevOps Labs

Personal lab definitions are grouped by domain, then provider, OS, installer, and profile.

```text
devops/local/
  kubernetes/<provider>/<os>/<installer>/<profile>/
  storage/<provider>/<os>/<tool>/<profile>/
  data/<provider>/<os>/<tool>/<profile>/
  apps/<provider>/<os>/<tool>/<app>/
```

Examples:

- `kubernetes/vagrant/ubuntu/kubeadm/basic`
- `kubernetes/vagrant/ubuntu/kubespray/rook-ceph`
- `kubernetes/kvm/ubuntu/kubeadm/gpu`
- `storage/vagrant/ubuntu/cephadm/basic`
- `data/vagrant/ubuntu/hadoop/basic`
