#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="mlrun"
RELEASE="mlrun"
VALUES_FILE="${ROOT_DIR}/values/mlrun-values.yaml"
CHART_PATH="${ROOT_DIR}/charts/mlrun"   # Local MLRun chart path

echo "=============================="
echo "🔹 Phase 6: MLRun Deployment (Local Chart & Offline Ready)"
echo "=============================="

# Ensure namespace exists
kubectl get ns $NAMESPACE >/dev/null 2>&1 || kubectl create namespace $NAMESPACE

# 1️⃣ Verify local MLRun chart
if [[ ! -d "$CHART_PATH" ]]; then
  echo "❌ Local MLRun chart not found at: $CHART_PATH"
  echo "   Please clone MLRun repo into charts/ like:"
  echo "       mkdir -p ${ROOT_DIR}/charts && cd ${ROOT_DIR}/charts"
  echo "       git clone https://github.com/mlrun/mlrun.git mlrun"
  exit 1
fi

# 2️⃣ Helm deploy MLRun from local path
echo "🔹 Installing MLRun from local chart..."
helm upgrade --install $RELEASE "$CHART_PATH/helm/mlrun" \
    -n $NAMESPACE \
    -f "$VALUES_FILE" \
    --create-namespace \
    --wait

# 3️⃣ Wait for core MLRun components
echo "🔹 Waiting for MLRun core pods..."
kubectl rollout status deployment/${RELEASE}-api -n $NAMESPACE --timeout=600s || true
kubectl rollout status deployment/${RELEASE}-ui -n $NAMESPACE --timeout=600s || true

echo "=============================="
echo "✅ MLRun deployed successfully from local chart!"
echo "🌐 Access: https://mlrun.core.harbor.domain/"
echo "=============================="

echo "ℹ️ Offline Mode Switch:"
echo "  1. Push all MLRun images to Harbor"
echo "  2. Set global.imageRegistry=core.harbor.domain/mlops-images in values/mlrun-values.yaml"
echo "  3. Rerun this script"
