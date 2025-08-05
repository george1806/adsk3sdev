#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
VALUES_FILE="${ROOT_DIR}/values/mlrun-values.yaml"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ Missing .env file at $ENV_FILE"
    exit 1
fi

# Load environment variables
set -a; source "$ENV_FILE"; set +a

: "${INSTALL_MODE:?Must set INSTALL_MODE=local or harbor in .env}"
: "${HARBOR_DOMAIN:?Missing HARBOR_DOMAIN in .env}"
: "${HARBOR_PROJECT:?Missing HARBOR_PROJECT in .env}"
: "${MLRUN_VERSION:?Missing MLRun version in .env}"

NAMESPACE="mlrun"
RELEASE="mlrun-ce"
OFFLINE_IMAGES_DIR="${ROOT_DIR}/offline-images"
CHARTS_DIR="${ROOT_DIR}/charts/mlrun-ce/charts/mlrun-ce"

echo "=============================="
echo "🔹 Phase 8: MLRun CE Deployment"
echo "=============================="
echo "ℹ️ Namespace: ${NAMESPACE}"
echo "ℹ️ Install Mode: ${INSTALL_MODE}"
echo "ℹ️ MLRun Version: ${MLRUN_VERSION}"

# Create namespace
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# -------------------------
# Function: Install MLRun CE
# -------------------------
install_mlrun() {
    echo "🔹 Installing MLRun CE Helm chart..."
    helm upgrade --install "$RELEASE" "$CHARTS_DIR" \
        -n "$NAMESPACE" \
        -f "$VALUES_FILE" \
        --create-namespace \
        --wait
}

# -------------------------
# Handle image loading
# -------------------------
if [[ "$INSTALL_MODE" == "local" ]]; then
    echo "🔹 Loading images from local tar files in $OFFLINE_IMAGES_DIR"
    for tarfile in "$OFFLINE_IMAGES_DIR"/*.tar; do
        echo "   -> Loading $tarfile into K3s containerd"
        sudo k3s ctr images import "$tarfile"
    done
elif [[ "$INSTALL_MODE" == "harbor" ]]; then
    echo "🔹 Using images from Harbor: $HARBOR_DOMAIN/$HARBOR_PROJECT"
else
    echo "❌ Invalid INSTALL_MODE: $INSTALL_MODE"
    exit 1
fi

# Install MLRun CE
install_mlrun

echo "=============================="
echo "✅ MLRun CE Installation Completed!"
echo "📌 Access URLs:"
echo "  MLRun UI:       https://mlrun.core.harbor.domain/"
echo "  JupyterHub:     https://jupyter.mlrun.core.harbor.domain/"
echo "  MinIO:          https://minio.mlrun.core.harbor.domain/"
echo "  Grafana:        https://grafana.mlrun.core.harbor.domain/"
echo "  Prometheus:     https://prometheus.mlrun.core.harbor.domain/"
echo "  (Optional) Nuclio: https://nuclio.mlrun.core.harbor.domain/"
echo
echo "ℹ️ Keycloak integration is available, uncomment in values file to enable."
