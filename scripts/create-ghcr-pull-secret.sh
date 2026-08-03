#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="${NAMESPACE:-image-webapp}"
GHCR_USERNAME="${GHCR_USERNAME:-justlee2512}"
GHCR_TOKEN="${GHCR_TOKEN:-}"

if [[ -z "${GHCR_TOKEN}" ]]; then
  echo "ERROR: Export GHCR_TOKEN nếu package GHCR đang để private." >&2
  exit 1
fi

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "${NAMESPACE}" create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username="${GHCR_USERNAME}" \
  --docker-password="${GHCR_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Sau đó thêm imagePullSecrets vào Deployment nếu image vẫn private."
