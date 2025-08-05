#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ .env file not found at $ENV_FILE"
    exit 1
fi

# Load environment variables
set -a; source "$ENV_FILE"; set +a

: "${HARBOR_DOMAIN:?Missing in .env}"
: "${HARBOR_TLS_SECRET:?Missing in .env}"

echo "=============================="
echo "🔹 Configure K3s to trust Harbor registry"
echo "=============================="

# Containerd certs directory for Harbor
CERTS_DIR="/etc/rancher/k3s/certs.d/${HARBOR_DOMAIN}"
sudo mkdir -p "${CERTS_DIR}"

# Extract Harbor TLS cert from k8s secret
echo "🔹 Extracting Harbor TLS certificate to ${CERTS_DIR}/ca.crt"
kubectl get secret "$HARBOR_TLS_SECRET" -n harbor -o jsonpath='{.data.tls\.crt}' \
    | base64 -d | sudo tee "${CERTS_DIR}/ca.crt" >/dev/null

# Prepare K3s registry config
REGISTRY_CONFIG="/etc/rancher/k3s/registries.yaml"

echo "🔹 Updating ${REGISTRY_CONFIG} with config_path method"

sudo tee "$REGISTRY_CONFIG" >/dev/null <<EOF
mirrors:
  ${HARBOR_DOMAIN}:
    endpoint:
      - "https://${HARBOR_DOMAIN}"

configs: {}
config_path: /etc/rancher/k3s/certs.d
EOF

# Apply permissions
sudo chmod 755 -R /etc/rancher/k3s/certs.d

# Restart K3s to apply
echo "🔹 Restarting K3s to apply new registry config..."
sudo systemctl restart k3s

# Validate using crictl
echo "🔹 Validating containerd can pull from Harbor..."
if ! sudo k3s crictl pull "${HARBOR_DOMAIN}/hello-world:latest" >/dev/null 2>&1; then
    echo "⚠️ Warning: Could not pull test image from Harbor. Check certs & DNS."
else
    echo "✅ Harbor registry trust successfully configured!"
fi
