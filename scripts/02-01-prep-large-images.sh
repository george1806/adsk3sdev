#!/usr/bin/env bash
set -euo pipefail

########################################
# 🔧 CONFIG (toggle here)
########################################

# Enable/disable stages
ENABLE_PULL_SAVE=true
ENABLE_PUSH_HARBOR=true  

# Images to prepare
IMAGES=(
  "trinodb/trino:449"
  "bitnami/spark:3.5.1"
)

# Save behavior
OFFLINE_DIR="./offline-images"
COMPRESS=true

# Push behavior
MAX_PUSH_RETRIES=2
RETRY_SLEEP=10

########################################
# 🔐 ENV + PATHS
########################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ROOT_DIR}/.env"
LOG_FILE="${ROOT_DIR}/images-list.txt"
CERTS_DIR="/etc/docker/certs.d"

[[ -f "$ENV_FILE" ]] || { echo "❌ Missing .env at $ENV_FILE"; exit 1; }
set -a; source "$ENV_FILE"; set +a

: "${HARBOR_DOMAIN:?Missing HARBOR_DOMAIN in .env}"
: "${HARBOR_PROJECT:?Missing HARBOR_PROJECT in .env}"
: "${HARBOR_USER:?Missing HARBOR_USER in .env}"
: "${HARBOR_PASS:?Missing HARBOR_PASS in .env}"
# Optional: HARBOR_TLS_SECRET (k8s secret containing tls.crt)

mkdir -p "$OFFLINE_DIR"
> "$LOG_FILE"

########################################
# 🧠 Helpers
########################################

die() { echo "❌ $*" >&2; exit 1; }

sanitize() {
  echo "$1" | sed 's|/|_|g; s|:|-|g'
}

ensure_harbor_project() {
  echo "🔹 Ensuring Harbor project '${HARBOR_PROJECT}' exists..."
  local exists
  exists=$(curl -sk -u "${HARBOR_USER}:${HARBOR_PASS}" \
    "https://${HARBOR_DOMAIN}/api/v2.0/projects?name=${HARBOR_PROJECT}" \
    | grep -c "\"name\":\"${HARBOR_PROJECT}\"" || true)
  if [[ "$exists" -eq 0 ]]; then
    curl -sk -u "${HARBOR_USER}:${HARBOR_PASS}" -X POST \
      "https://${HARBOR_DOMAIN}/api/v2.0/projects" \
      -H "Content-Type: application/json" \
      -d "{\"project_name\": \"${HARBOR_PROJECT}\", \"public\": true}" >/dev/null \
      || die "Failed to create Harbor project ${HARBOR_PROJECT}"
    echo "✅ Created project '${HARBOR_PROJECT}'."
  else
    echo "ℹ️ Project '${HARBOR_PROJECT}' already exists."
  fi
}

maybe_trust_harbor_tls() {
  if [[ -n "${HARBOR_TLS_SECRET:-}" ]]; then
    echo "🔹 Preparing Harbor cert for Docker trust..."
    sudo mkdir -p "${CERTS_DIR}/${HARBOR_DOMAIN}"
    if kubectl get secret "${HARBOR_TLS_SECRET}" -n harbor >/dev/null 2>&1; then
      kubectl get secret "${HARBOR_TLS_SECRET}" -n harbor -o jsonpath="{.data.tls\.crt}" \
        | base64 -d | sudo tee "${CERTS_DIR}/${HARBOR_DOMAIN}/ca.crt" >/dev/null
      sudo systemctl restart docker || true
      echo "✅ Docker now trusts Harbor at ${HARBOR_DOMAIN}"
    else
      echo "⚠️ Could not find secret ${HARBOR_TLS_SECRET} in namespace harbor."
    fi
  fi
}

docker_login_harbor() {
  echo "🔹 Logging into Harbor..."
  echo "$HARBOR_PASS" | docker login "$HARBOR_DOMAIN" -u "$HARBOR_USER" --password-stdin \
    || die "Docker login to ${HARBOR_DOMAIN} failed"
}

save_image() {
  local img="$1"
  local base tarfile
  base="$(sanitize "$img")"
  tarfile="${OFFLINE_DIR}/${base}.tar"

  echo "→ Pulling $img"
  docker pull "$img"

  echo "→ Saving $img → ${tarfile}$([[ $COMPRESS == true ]] && echo '.gz')"
  if [[ "$COMPRESS" == "true" ]]; then
    docker save "$img" | gzip -c > "${tarfile}.gz"
    echo "$img => ${tarfile}.gz" >> "$LOG_FILE"
  else
    docker save -o "${tarfile}" "$img"
    echo "$img => ${tarfile}" >> "$LOG_FILE"
  fi
}

push_with_retry() {
  local src="$1"
  local name_tag="${src##*/}"
  local name="${name_tag%%:*}"
  local tag="${src##*:}"
  local dst="${HARBOR_DOMAIN}/${HARBOR_PROJECT}/${name}:${tag}"

  echo "→ Tag & push $src → $dst"
  docker pull "$src"
  docker tag "$src" "$dst"

  local attempt=1
  while :; do
    if docker push "$dst"; then
      echo "$src -> $dst" >> "$LOG_FILE"
      return 0
    fi
    if (( attempt >= MAX_PUSH_RETRIES )); then
      echo "❌ Push failed after ${MAX_PUSH_RETRIES} attempts: $dst"
      return 1
    fi
    echo "⚠️ Push failed (attempt $attempt). Retrying in ${RETRY_SLEEP}s..."
    sleep "$RETRY_SLEEP"
    ((attempt++))
  done
}

########################################
# 🚀 Run
########################################

if [[ "$ENABLE_PULL_SAVE" == "true" ]]; then
  echo "=============================="
  echo "🔹 Stage: PULL & SAVE locally → ${OFFLINE_DIR}"
  echo "=============================="
  for img in "${IMAGES[@]}"; do
    save_image "$img"
  done
  echo "✅ Saved all images. (List: $LOG_FILE)"
fi

if [[ "$ENABLE_PUSH_HARBOR" == "true" ]]; then
  echo "=============================="
  echo "🔹 Stage: PUSH to Harbor → ${HARBOR_DOMAIN}/${HARBOR_PROJECT}"
  echo "=============================="
  maybe_trust_harbor_tls
  docker_login_harbor
  ensure_harbor_project
  for img in "${IMAGES[@]}"; do
    push_with_retry "$img"
  done
  echo "✅ Pushed all images to Harbor. (Map: $LOG_FILE)"
fi

if [[ "$ENABLE_PULL_SAVE" != "true" && "$ENABLE_PUSH_HARBOR" != "true" ]]; then
  echo "⚠️ Both stages are disabled. Nothing to do."
fi
