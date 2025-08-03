#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="keycloak"
RELEASE="keycloak"
VALUES_FILE="${ROOT_DIR}/values/keycloak-values.yaml"
CHART_REF="bitnami/keycloak"   # Offline Helm chart must be preloaded or locally available

echo "=============================="
echo "🔹 Phase 3: Offline Keycloak Deployment"
echo "=============================="

# 1️⃣ Create namespace if not exists
kubectl get ns $NAMESPACE >/dev/null 2>&1 || kubectl create namespace $NAMESPACE

# 2️⃣ Check for existing release & crashlooping pods
if helm status $RELEASE -n $NAMESPACE >/dev/null 2>&1; then
    CRASHING=$(kubectl get pods -n $NAMESPACE \
        --selector app.kubernetes.io/name=keycloak \
        --field-selector=status.phase!=Running \
        --no-headers | grep -c "CrashLoopBackOff" || true)
    if [[ "$CRASHING" -gt 0 ]]; then
        echo "⚠️ Existing Keycloak release detected with CrashLooping pods. Cleaning up..."
        helm uninstall $RELEASE -n $NAMESPACE || true

        # Optional: wipe PVC for a full clean slate (uncomment if needed)
        # echo "🧹 Deleting PVCs for a fresh DB (warning: wipes Keycloak DB)"
        # kubectl delete pvc -n $NAMESPACE --selector app.kubernetes.io/instance=$RELEASE || true
    else
        echo "ℹ️ Upgrading existing Keycloak release..."
    fi
fi

# 3️⃣ Deploy Keycloak + PostgreSQL
echo "🔹 Deploying Keycloak + PostgreSQL..."
helm upgrade --install $RELEASE $CHART_REF \
    -n $NAMESPACE \
    -f "$VALUES_FILE" \
    --create-namespace

# 4️⃣ Monitor pods until Ready
echo "🔹 Waiting for Keycloak pods to start (watching logs)..."
kubectl rollout status sts/$RELEASE -n $NAMESPACE --timeout=180s || true

# 5️⃣ Print admin credentials
echo "🔹 Retrieving admin credentials..."
KC_ADMIN_USER=$(kubectl get secret $RELEASE -n $NAMESPACE -o jsonpath="{.data.admin-user}" | base64 -d)
KC_ADMIN_PASS=$(kubectl get secret $RELEASE -n $NAMESPACE -o jsonpath="{.data.admin-password}" | base64 -d)

echo "=============================="
echo "✅ Keycloak deployed successfully!"
echo "🌐 Access: https://keycloak.core.harbor.domain/"
echo "👤 Admin user: $KC_ADMIN_USER"
echo "🔑 Admin password: $KC_ADMIN_PASS"
echo "=============================="

echo "ℹ️ Use: kubectl get pods -n $NAMESPACE -w  to monitor pod status"
