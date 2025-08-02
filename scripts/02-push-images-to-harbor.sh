#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Load .env File Safely
# ==============================
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ .env file not found at $ENV_FILE"
    exit 1
fi

# Load variables safely (ignoring comments)
set -o allexport
source "$ENV_FILE"
set +o allexport

# Validate required variables
: "${HARBOR_DOMAIN:?Missing in .env}"
: "${HARBOR_USER:?Missing in .env}"
: "${HARBOR_PASS:?Missing in .env}"
: "${HARBOR_PROJECT:=mlops}"         # Default to mlops if not set
: "${HARBOR_TLS_SECRET:?Missing in .env}"

# ==============================
# 1️⃣ Verify Harbor Connectivity
# ==============================
echo "🔹 Checking Harbor connectivity..."
if ! ping -c 1 "${HARBOR_DOMAIN}" >/dev/null 2>&1; then
  echo "❌ Cannot resolve ${HARBOR_DOMAIN}. Check /etc/hosts or DNS."
  exit 1
fi

# ==============================
# 2️⃣ Install Harbor Certificate for Docker
# ==============================
echo "🔹 Extracting Harbor TLS certificate for Docker trust..."
CERTS_DIR="/etc/docker/certs.d/${HARBOR_DOMAIN}"
sudo mkdir -p "${CERTS_DIR}"

kubectl get secret "${HARBOR_TLS_SECRET}" -n harbor -o jsonpath="{.data.tls\.crt}" \
    | base64 -d | sudo tee "${CERTS_DIR}/ca.crt" >/dev/null

sudo systemctl restart docker
echo "✅ Docker now trusts Harbor at ${HARBOR_DOMAIN}"

# ==============================
# 3️⃣ Harbor Login
# ==============================
echo "🔹 Logging into Harbor..."
docker login "${HARBOR_DOMAIN}" -u "${HARBOR_USER}" -p "${HARBOR_PASS}"

# ==============================
# 4️⃣ Ensure Project Exists
# ==============================
echo "🔹 Ensuring Harbor project '${HARBOR_PROJECT}' exists..."
EXISTS=$(curl -sk -u "${HARBOR_USER}:${HARBOR_PASS}" \
    "https://${HARBOR_DOMAIN}/api/v2.0/projects?name=${HARBOR_PROJECT}" \
    | grep -c "\"name\":\"${HARBOR_PROJECT}\"" || true)

if [ "$EXISTS" -eq 0 ]; then
    echo "🔹 Creating project '${HARBOR_PROJECT}'..."
    curl -sk -u "${HARBOR_USER}:${HARBOR_PASS}" -X POST \
        "https://${HARBOR_DOMAIN}/api/v2.0/projects" \
        -H "Content-Type: application/json" \
        -d "{\"project_name\": \"${HARBOR_PROJECT}\", \"public\": true}"
else
    echo "ℹ️ Project '${HARBOR_PROJECT}' already exists."
fi

# ==============================
# 5️⃣ Images to Pull & Push
# ==============================
images=(
  "traefik:latest traefik"
  "bitnami/keycloak:24.0.5 keycloak"
  "bitnami/postgresql:16.2.0 postgresql"
  "bitnami/jupyterhub:4.1.5 jupyterhub"
  "mlrun/mlrun:1.7.0 mlrun"
  "apache/airflow:2.9.0 airflow"
)

> "${ROOT_DIR}/images-list.txt"

for item in "${images[@]}"; do
  src=$(echo "$item" | awk '{print $1}')
  name=$(echo "$item" | awk '{print $2}')
  tag=$(echo "$src" | awk -F: '{print $2}')

  echo "=============================="
  echo "🔹 Processing $src"

  docker pull "$src"

  dst="${HARBOR_DOMAIN}/${HARBOR_PROJECT}/${name}:${tag}"
  docker tag "$src" "$dst"
  docker push "$dst"

  echo "$src -> $dst" >> "${ROOT_DIR}/images-list.txt"
done

echo "✅ All images pushed successfully!"
echo "📄 Mappings saved to ${ROOT_DIR}/images-list.txt"
