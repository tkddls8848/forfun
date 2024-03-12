#!/usr/bin/bash

# install kustomize
sudo curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash

# get kubeflow file
sudo git clone https://github.com/kubeflow/manifests.git
cd manifests

# install all kubeflow components with one command
while ! kustomize build example | kubectl apply -f -; do echo "Retrying to apply resources"; sleep 10; done
