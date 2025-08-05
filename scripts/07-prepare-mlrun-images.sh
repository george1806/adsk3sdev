#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
CHARTS_DIR="${ROOT_DIR}/charts"
LOG_FILE="${ROOT_DIR}/images-list.txt"
LOCAL_IMG_DIR="${ROOT_DIR}/offline-images"

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

mkdir -p "$CHARTS_DIR" "$LOCAL_IMG_DIR"
> "$LOG_FILE"

prepare_images_local() {
    echo "=============================="
    echo "🔹 Stage 1: Clone MLRun CE & Save Images Locally"
    echo "=============================="

    cd "$CHARTS_DIR"

    # Clone MLRun CE repo if not exists
    if [[ ! -d "mlrun-ce" ]]; then
        echo "🔹 Cloning MLRun CE repository..."
        git clone https://github.com/mlrun/ce.git mlrun-ce
    fi

    cd mlrun-ce
    git fetch --tags
    LATEST_TAG=$(git tag -l "mlrun-ce-[0-9]*" | grep -v "rc" | sort -V | tail -n1)
    echo "ℹ️ Using tag: ${LATEST_TAG}"
    git checkout "${LATEST_TAG}"

    CHART_PATH="charts/mlrun-ce"
    if [[ ! -d "$CHART_PATH" ]]; then
        echo "❌ Helm chart path not found: $CHART_PATH"
        exit 1
    fi

    echo "🔹 Updating chart dependencies..."
    helm dependency update "$CHART_PATH"

    echo "🔹 Extracting image list..."
    IMAGE_LIST=$(helm template mlrun-ce "$CHART_PATH" \
      | grep 'image:' \
      | awk '{print $2}' \
      | sed "s/['\"]//g" \
      | grep -E '.+/.+:.+' \
      | sort -u)

    if [[ -z "$IMAGE_LIST" ]]; then
        echo "❌ No valid images found from Helm template."
        exit 1
    fi

    echo "🔹 Pulling and saving images locally to $LOCAL_IMG_DIR"
    for IMG in $IMAGE_LIST; do
        [[ -z "$IMG" ]] && continue
        echo "=============================="
        echo "Processing image: $IMG"

        docker pull "$IMG"

        FILE_NAME=$(basename "${IMG%%:*}")-$(echo "$IMG" | awk -F: '{print $2}').tar
        docker save "$IMG" -o "${LOCAL_IMG_DIR}/${FILE_NAME}"

        echo "$IMG -> ${LOCAL_IMG_DIR}/${FILE_NAME}" >> "$LOG_FILE"
    done

    # Include PostgreSQL image for offline
    PG_SRC="postgres:16.2"
    echo "=============================="
    echo "Processing PostgreSQL image: $PG_SRC"
    docker pull "$PG_SRC"
    docker save "$PG_SRC" -o "${LOCAL_IMG_DIR}/postgresql-16.2.0.tar"
    echo "$PG_SRC -> ${LOCAL_IMG_DIR}/postgresql-16.2.0.tar" >> "$LOG_FILE"

    echo "✅ All images prepared locally at $LOCAL_IMG_DIR"
    echo "📄 Mapping saved at $LOG_FILE"
}

push_images_to_harbor() {
    echo "=============================="
    echo "🔹 Stage 2: Push Images to Harbor"
    echo "=============================="

    echo "$HARBOR_PASS" | docker login "$HARBOR_DOMAIN" -u "$HARBOR_USER" --password-stdin

    while read -r line; do
        SRC=$(echo "$line" | awk '{print $1}')
        NAME=$(basename "${SRC%%:*}")
        TAG=$(echo "$SRC" | awk -F: '{print $2}')
        DST="${HARBOR_DOMAIN}/${HARBOR_PROJECT}/${NAME}:${TAG}"

        echo "=============================="
        echo "Pushing image to Harbor: $DST"

        docker tag "$SRC" "$DST"
        docker push "$DST"
    done < "$LOG_FILE"

    echo "✅ All images pushed to Harbor!"
}

# ==============================
# Execute stages
# ==============================

prepare_images_local
# push_images_to_harbor   # Uncomment when ready to push to Harbor
