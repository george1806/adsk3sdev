#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="jupyterhub"
RELEASE="jupyterhub"
VALUES_FILE="${ROOT_DIR}/values/jupyterhub-values.yaml"

echo "=============================="
echo "🔹 Phase 5: JupyterHub Deployment (SQLite PVC Mode)"
echo "=============================="

# Ensure namespace exists
kubectl get ns $NAMESPACE >/dev/null 2>&1 || kubectl create namespace $NAMESPACE

# Add JupyterHub Helm repo
if ! helm repo list | grep -q jupyterhub; then
  helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
fi
helm repo update

echo "🔹 Installing JupyterHub (SQLite PVC)..."
helm upgrade --install $RELEASE jupyterhub/jupyterhub \
    -n $NAMESPACE \
    -f "$VALUES_FILE" \
    --create-namespace \
    --wait

echo "🔹 Waiting for JupyterHub hub pod to be ready..."
kubectl rollout status deployment/${RELEASE}-hub -n $NAMESPACE --timeout=600s || true

echo "=============================="
echo "✅ JupyterHub deployed successfully (SQLite mode)!"
echo "🌐 Access: https://jupyterhub.core.harbor.domain/"
echo "=============================="
echo "ℹ️ Switch to PostgreSQL later by:"
echo "  1. Deploying independent PostgreSQL"
echo "  2. Updating hub.db.type and hub.db.url"
echo "  3. Rerunning this script"
