#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="${NAMESPACE:-image-webapp}"
DATABASE_URL="${DATABASE_URL:-}"
SESSION_SECRET="${SESSION_SECRET:-}"

if [[ -z "${DATABASE_URL}" ]]; then
  echo "ERROR: Hãy export DATABASE_URL trước khi chạy." >&2
  echo "Ví dụ: export DATABASE_URL='postgresql://webapp:PASS@192.168.2.90:5432/webapp'" >&2
  exit 1
fi

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

if [[ -z "${SESSION_SECRET}" ]]; then
  if kubectl -n "${NAMESPACE}" get secret image-webapp-secret >/dev/null 2>&1; then
    SESSION_SECRET="$(kubectl -n "${NAMESPACE}" get secret image-webapp-secret \
      -o jsonpath='{.data.SESSION_SECRET}' | base64 -d)"
    echo "Đang tái sử dụng SESSION_SECRET hiện có."
  else
    SESSION_SECRET="$(openssl rand -base64 48 | tr -d '\n')"
    echo "Đã tự tạo SESSION_SECRET mới."
  fi
fi

kubectl -n "${NAMESPACE}" create secret generic image-webapp-secret \
  --from-literal=DATABASE_URL="${DATABASE_URL}" \
  --from-literal=SESSION_SECRET="${SESSION_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" get secret image-webapp-secret
