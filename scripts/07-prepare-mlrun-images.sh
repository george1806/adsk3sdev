#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
CHARTS_DIR="${ROOT_DIR}/charts"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Missing .env file"; exit 1
fi
set -a; source "$ENV_FILE"; set +a

mkdir -p "$CHARTS_DIR"
cd "$CHARTS_DIR"

# Clone MLRun CE repo if not exists
if [[ ! -d "mlrun-ce" ]]; then
  echo "🔹 Cloning MLRun CE repo..."
  git clone https://github.com/mlrun/ce.git mlrun-ce
fi

cd mlrun-ce
git fetch --tags
LATEST_TAG=$(git tag -l "mlrun-ce-[0-9]*" | grep -v "rc" | sort -V | tail -n1)
echo "ℹ️ Using tag: ${LATEST_TAG}"
git checkout "${LATEST_TAG}"

# Chart path is valid under charts/mlrun-ce
CHART_PATH="charts/mlrun-ce"
helm dependency update "$CHART_PATH"

echo "🔹 Extracting image list..."
IMAGE_LIST=$(helm template mlrun-ce "$CHART_PATH" \
  --set global.registry.url="" 2>/dev/null | \
  grep "image:" | awk '{print $2}' | sort -u)

echo "🔹 Logging into Harbor..."
echo "$HARBOR_PASS" | docker login "$HARBOR_DOMAIN" -u "$HARBOR_USER" --password-stdin

> "${ROOT_DIR}/images-list.txt"

for IMG in $IMAGE_LIST; do
  SRC="$IMG"
  NAME=$(basename "${IMG%%:*}")
  TAG=$(echo "$IMG" | awk -F: '{print $2}')
  DST="${HARBOR_DOMAIN}/${HARBOR_PROJECT}/${NAME}:${TAG}"

  echo "=============================="
  echo "Processing image: $SRC"
  docker pull "$SRC"
  docker tag "$SRC" "$DST"
  docker push "$DST"

  echo "$SRC -> $DST" >> "${ROOT_DIR}/images-list.txt"
done

# Push PostgreSQL (offline ready)
docker pull postgres:16.2
docker tag postgres:16.2 "${HARBOR_DOMAIN}/${HARBOR_PROJECT}/postgresql:16.2.0"
docker push "${HARBOR_DOMAIN}/${HARBOR_PROJECT}/postgresql:16.2.0"

echo "✅ MLRun CE and PostgreSQL images pushed to Harbor."
