#!/bin/bash
set -euo pipefail

echo "🔹 Installing K3s (single-node control plane)..."
curl -sfL https://get.k3s.io | sh -

echo "🔹 Waiting for K3s to start..."
sleep 15
sudo systemctl enable k3s
sudo systemctl start k3s

echo "🔹 Configuring kubectl..."
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
export KUBECONFIG=~/.kube/config

# Make kubectl available globally
sudo ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

echo "🔹 Verifying K3s cluster..."
kubectl get nodes
kubectl get pods -A

echo "🔹 Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "🔹 Verifying Helm..."
helm version

echo "✅ K3s, kubectl, and Helm installed and ready!"
echo "   You can now deploy your apps with kubectl or Helm."
