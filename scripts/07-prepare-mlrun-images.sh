#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
CHARTS_DIR="${ROOT_DIR}/charts"
LOG_FILE="${ROOT_DIR}/images-list.txt"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ Missing .env file at $ENV_FILE"
    exit 1
fi

# Load environment variables
set -a; source "$ENV_FILE"; set +a

: "${HARBOR_DOMAIN:?Missing in .env}"
: "${HARBOR_USER:?Missing in .env}"
: "${HARBOR_PASS:?Missing in .env}"
: "${HARBOR_PROJECT:?Missing in .env}"

echo "=============================="
echo "🔹 Phase 7: Prepare MLRun CE Images for Harbor"
echo "=============================="

mkdir -p "$CHARTS_DIR"
cd "$CHARTS_DIR"

# 1️⃣ Clone MLRun CE repo if not exists
if [[ ! -d "mlrun-ce" ]]; then
    echo "🔹 Cloning MLRun CE repository..."
    git clone https://github.com/mlrun/ce.git mlrun-ce
fi

cd mlrun-ce
git fetch --tags
LATEST_TAG=$(git tag -l "mlrun-ce-[0-9]*" | grep -v "rc" | sort -V | tail -n1)
echo "ℹ️ Using tag: ${LATEST_TAG}"
git checkout "${LATEST_TAG}"

# 2️⃣ Helm chart path
CHART_PATH="charts/mlrun-ce"
if [[ ! -d "$CHART_PATH" ]]; then
    echo "❌ Helm chart path not found: $CHART_PATH"
    exit 1
fi

# 3️⃣ Update chart dependencies
helm dependency update "$CHART_PATH"

# 4️⃣ Extract image list safely
echo "🔹 Extracting image list..."
IMAGE_LIST=$(helm template mlrun-ce "$CHART_PATH" \
  | grep 'image:' \
  | awk '{print $2}' \
  | tr -d '"' \
  | grep -E '.+/.+:.+' \
  | sort -u)

if [[ -z "$IMAGE_LIST" ]]; then
    echo "❌ No valid images found from Helm template."
    exit 1
fi

echo "🔹 Logging into Harbor..."
echo "$HARBOR_PASS" | docker login "$HARBOR_DOMAIN" -u "$HARBOR_USER" --password-stdin

> "$LOG_FILE"

# 5️⃣ Process images
for IMG in $IMAGE_LIST; do
    [[ -z "$IMG" ]] && continue

    echo "=============================="
    echo "Processing image: $IMG"

    SRC="$IMG"
    NAME=$(basename "${SRC%%:*}")
    TAG=$(echo "$SRC" | awk -F: '{print $2}')
    DST="${HARBOR_DOMAIN}/${HARBOR_PROJECT}/${NAME}:${TAG}"

    docker pull "$SRC"
    docker tag "$SRC" "$DST"
    docker push "$DST"

    echo "$SRC -> $DST" >> "$LOG_FILE"
done

# 6️⃣ Push PostgreSQL image (offline ready)
PG_SRC="postgres:16.2"
PG_DST="${HARBOR_DOMAIN}/${HARBOR_PROJECT}/postgresql:16.2.0"
echo "=============================="
echo "Processing PostgreSQL image: $PG_SRC"
docker pull "$PG_SRC"
docker tag "$PG_SRC" "$PG_DST"
docker push "$PG_DST"
echo "$PG_SRC -> $PG_DST" >> "$LOG_FILE"

echo "=============================="
echo "✅ All images pushed successfully to Harbor!"
echo "📄 Image mapping saved at $LOG_FILE"
