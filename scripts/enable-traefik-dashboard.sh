#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFESTS_DIR="/var/lib/rancher/k3s/server/manifests"
VALUES_FILE="$ROOT_DIR/values/traefik-config.yaml"
INGRESS_FILE="$ROOT_DIR/manifests/traefik-dashboard-ingress.yaml"
DASHBOARD_DOMAIN="traefik.core.harbor.domain"

echo "=============================="
echo "🔹 Enabling Traefik Dashboard (Default K3s)"
echo "=============================="

# 1️⃣ Apply HelmChartConfig to enable dashboard
if [[ -f "$VALUES_FILE" ]]; then
  echo "🔹 Copying HelmChartConfig to K3s manifests..."
  sudo cp "$VALUES_FILE" "$MANIFESTS_DIR/traefik-config.yaml"
else
  echo "❌ HelmChartConfig file not found at $VALUES_FILE"
  exit 1
fi

# 2️⃣ Restart K3s to reconcile Helm
echo "🔹 Restarting K3s to apply dashboard config..."
sudo systemctl restart k3s
sleep 5

# 3️⃣ Wait for Traefik to be ready
echo "🔹 Waiting for Traefik pod rollout..."
kubectl rollout status deployment traefik -n kube-system --timeout=2m

# 4️⃣ Apply IngressRoute to expose dashboard
if [[ -f "$INGRESS_FILE" ]]; then
  kubectl apply -f "$INGRESS_FILE"
else
  echo "❌ IngressRoute file not found at $INGRESS_FILE"
  exit 1
fi

# 5️⃣ Update /etc/hosts for local resolution
if ! grep -q "$DASHBOARD_DOMAIN" /etc/hosts; then
  echo "127.0.0.1 $DASHBOARD_DOMAIN" | sudo tee -a /etc/hosts
  echo "✅ Added $DASHBOARD_DOMAIN to /etc/hosts"
else
  echo "ℹ️ Host already in /etc/hosts"
fi

echo "=============================="
echo "✅ Traefik dashboard is now available at:"
echo "   https://$DASHBOARD_DOMAIN/dashboard/"
echo "=============================="
