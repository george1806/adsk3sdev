#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="postgres"
RELEASE="independent-postgres"
VALUES_FILE="${ROOT_DIR}/values/postgresql-values.yaml"

echo "=============================="
echo "🔹 Phase X: Deploy Independent PostgreSQL (Offline Ready)"
echo "=============================="

kubectl get ns $NAMESPACE >/dev/null 2>&1 || kubectl create namespace $NAMESPACE

# Add Bitnami repo for PostgreSQL chart
if ! helm repo list | grep -q bitnami; then
  helm repo add bitnami https://charts.bitnami.com/bitnami
fi
helm repo update

echo "🔹 Installing PostgreSQL with Harbor image..."
helm upgrade --install $RELEASE bitnami/postgresql \
    -n $NAMESPACE \
    -f "$VALUES_FILE" \
    --create-namespace \
    --wait

echo "🔹 Waiting for PostgreSQL pod to be ready..."
kubectl rollout status statefulset/${RELEASE} -n $NAMESPACE --timeout=300s || true

echo "=============================="
echo "✅ Independent PostgreSQL deployed successfully!"
echo "📄 Connection info:"
echo "    Host: ${RELEASE}.${NAMESPACE}.svc.cluster.local"
echo "    Port: 5432"
echo "    User: admin"
echo "    Password: AdminP@ss123"
echo "    Default DB: defaultdb"
echo "=============================="
echo "ℹ️ Additional DBs created (via init script): app1db, app2db, app3db"
