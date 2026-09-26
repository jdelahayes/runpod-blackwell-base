#!/usr/bin/env bash
# Construit l'image de base et l'affiche avec sa taille finale.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

IMAGE_NAME="${IMAGE_NAME:-runpod-blackwell-base}"
IMAGE_TAG="${IMAGE_TAG:-cu130-torch2.14-py313}"
REGISTRY="${REGISTRY:-}" # ex: ghcr.io/tonuser

FULL_TAG="${IMAGE_NAME}:${IMAGE_TAG}"
if [[ -n "$REGISTRY" ]]; then
  FULL_TAG="${REGISTRY}/${FULL_TAG}"
fi

echo ">> Build ${FULL_TAG}"
docker buildx build \
  --platform linux/amd64 \
  --tag "${FULL_TAG}" \
  --tag "${IMAGE_NAME}:latest" \
  --cache-from "type=registry,ref=${FULL_TAG}-cache" \
  --cache-to "type=inline" \
  --load \
  .

echo
echo ">> Taille de l'image :"
docker images "${IMAGE_NAME}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
