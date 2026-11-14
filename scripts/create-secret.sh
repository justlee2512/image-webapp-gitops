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
  existing_session="$(kubectl -n "${NAMESPACE}" get secret image-drive \
    --ignore-not-found -o jsonpath='{.data.session-secret}')"
  if [[ -n "${existing_session}" ]]; then
    SESSION_SECRET="$(printf '%s' "${existing_session}" | base64 -d)"
    echo "Đang tái sử dụng SESSION_SECRET hiện có."
  else
    SESSION_SECRET="$(openssl rand -base64 48 | tr -d '\n')"
    echo "Đã tự tạo SESSION_SECRET mới."
  fi
fi

kubectl -n "${NAMESPACE}" create secret generic image-drive \
  --from-literal=database-url="${DATABASE_URL}" \
  --from-literal=session-secret="${SESSION_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" get secret image-drive
