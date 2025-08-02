#!/bin/bash
set -euo pipefail

NAMESPACE=harbor
RELEASE=harbor
DOMAIN=harbor.local

echo "🔹 Detecting K3s LAN IP..."
LAN_IP=$(hostname -I | awk '{print $1}')

echo "🔹 Updating kubeconfig to use ${LAN_IP}..."
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
sed -i "s/127.0.0.1/${LAN_IP}/" ~/.kube/config
export KUBECONFIG=~/.kube/config

# Persist KUBECONFIG
if ! grep -q "export KUBECONFIG=" ~/.bashrc; then
    echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
fi

echo "🔹 Creating namespace: ${NAMESPACE}..."
kubectl create namespace $NAMESPACE || true

echo "🔹 Adding Harbor Helm repo..."
helm repo add harbor https://helm.goharbor.io
helm repo update

echo "🔹 Installing Harbor via Helm..."
helm upgrade --install $RELEASE harbor/harbor \
  --namespace $NAMESPACE \
  -f ./values/harbor-values.yaml

echo "🔹 Waiting for Harbor pods to be ready..."
kubectl rollout status deployment/${RELEASE}-core -n $NAMESPACE --timeout=5m

# Configure local DNS
if ! grep -q "${DOMAIN}" /etc/hosts; then
  echo "127.0.0.1 ${DOMAIN}" | sudo tee -a /etc/hosts
fi

echo "✅ Harbor installed and accessible at https://${DOMAIN}"
