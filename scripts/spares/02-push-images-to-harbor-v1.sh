#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ .env file not found at $ENV_FILE"
    exit 1
fi

# Load env variables safely
set -o allexport
source "$ENV_FILE"
set +o allexport

: "${HARBOR_DOMAIN:?Missing in .env}"
: "${HARBOR_USER:?Missing in .env}"
: "${HARBOR_PASS:?Missing in .env}"
: "${HARBOR_PROJECT:=mlops}"
: "${HARBOR_TLS_SECRET:?Missing in .env}"

# Images to push: "source_image:tag target_repo semver(optional)"
images=(
  # Infrastructure
  # "traefik:latest traefik 3.1.0"
  # "bitnami/keycloak:24.0.5 keycloak"
  # "bitnami/postgresql:16.2.0 postgresql"

  # MLRun Core
  "mlrun/mlrun:1.7.0 mlrun-api"
  "mlrun/jupyter:1.7.0 mlrun-ui"
  "mlrun/ml-base:1.7.0 ml-base"
  "mlrun/ml-models:1.7.0 ml-models"

  # Artifact storage
  "minio/minio:RELEASE.2025-01-11T07-00-00Z minio 2025-01-11"
)

echo "🔹 Checking Harbor connectivity..."
ping -c 1 "${HARBOR_DOMAIN}" >/dev/null || {
  echo "❌ Cannot resolve ${HARBOR_DOMAIN}. Check /etc/hosts or DNS."
  exit 1
}

echo "🔹 Preparing Harbor cert for Docker..."
CERTS_DIR="/etc/docker/certs.d/${HARBOR_DOMAIN}"
sudo mkdir -p "${CERTS_DIR}"
kubectl get secret "${HARBOR_TLS_SECRET}" -n harbor -o jsonpath="{.data.tls\.crt}" \
    | base64 -d | sudo tee "${CERTS_DIR}/ca.crt" >/dev/null
sudo systemctl restart docker

echo "🔹 Logging into Harbor..."
docker login "${HARBOR_DOMAIN}" -u "${HARBOR_USER}" -p "${HARBOR_PASS}"

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

> "${ROOT_DIR}/images-list.txt"

retry_push() {
  local image="$1"
  local retries=5
  local delay=15

  for ((i=1; i<=retries; i++)); do
    echo "🔹 Attempt $i to push $image..."
    if docker push "$image"; then
      echo "✅ Push succeeded for $image"
      return 0
    fi
    echo "⚠️ Push failed, retrying in $delay seconds..."
    sleep $delay
  done

  echo "❌ Push failed after $retries attempts for $image"
  return 1
}

for item in "${images[@]}"; do
  src=$(echo "$item" | awk '{print $1}')        # source image
  name=$(echo "$item" | awk '{print $2}')       # target repo in Harbor
  semver=$(echo "$item" | awk '{print $3}') || true
  tag=$(echo "$src" | awk -F: '{print $2}')

  echo "=============================="
  echo "🔹 Processing $src"

  docker pull "$src"

  dst="${HARBOR_DOMAIN}/${HARBOR_PROJECT}/${name}:${tag}"
  docker tag "$src" "$dst"

  # Check image size in bytes
  image_id=$(docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" | grep "$src" | awk '{print $2}')
  size_bytes=$(docker image inspect "$image_id" --format '{{ .Size }}')
  size_gb=$(echo "scale=2; $size_bytes/1073741824" | bc)

  echo "ℹ️ Image size for $src: ${size_gb}GB"

  if (( $(echo "$size_gb > 1" | bc -l) )); then
    echo "⚠️ Large image detected, using save/load method to reduce push timeout..."
    tmp_tar="${ROOT_DIR}/tmp_${name}.tar"
    docker save "$dst" -o "$tmp_tar"
    docker load -i "$tmp_tar"
    retry_push "$dst"
    rm -f "$tmp_tar"
  else
    retry_push "$dst"
  fi

  echo "$src -> $dst" >> "${ROOT_DIR}/images-list.txt"

  # If a semver tag is defined, push that as well
  if [[ -n "${semver:-}" ]]; then
    semver_dst="${HARBOR_DOMAIN}/${HARBOR_PROJECT}/${name}:${semver}"
    docker tag "$src" "$semver_dst"
    retry_push "$semver_dst"
    echo "$src -> $semver_dst" >> "${ROOT_DIR}/images-list.txt"
    echo "ℹ️ Semver tag pushed for Helm: ${semver_dst}"
  fi
done

echo "✅ All images pushed successfully!"
echo "📄 Mappings saved to ${ROOT_DIR}/images-list.txt"
