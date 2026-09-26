#!/usr/bin/env bash
# Pousse l'image vers le registre. Nécessite REGISTRY (ex: ghcr.io/tonuser) et un `docker login` préalable.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

IMAGE_NAME="${IMAGE_NAME:-runpod-blackwell-base}"
IMAGE_TAG="${IMAGE_TAG:-cu130-torch2.14-py313}"
: "${REGISTRY:?Définis REGISTRY, ex: export REGISTRY=ghcr.io/tonuser}"

FULL_TAG="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
LATEST_TAG="${REGISTRY}/${IMAGE_NAME}:latest"

docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${FULL_TAG}"
docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${LATEST_TAG}"

docker push "${FULL_TAG}"
docker push "${LATEST_TAG}"

echo ">> Poussé : ${FULL_TAG} et ${LATEST_TAG}"
