#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$root/scripts/lib.sh"
load_env
require_command docker

if [[ "$(docker info --format '{{.Swarm.ControlAvailable}}')" != true ]]; then
  echo "deploy must run on a Swarm manager" >&2
  exit 1
fi

for image_var in GATEWAY_IMAGE FRONTEND_IMAGE BACKEND_IMAGE SWARM_CHECK_IMAGE; do
  require_immutable_image "$image_var"
done
for name_var in STACK_NAME API_NODE REDIS_NODE INFERENCE_NODE DATABASE_URL_SECRET \
  WORKER_DATABASE_URL_SECRET S3_ACCESS_KEY_ID_SECRET S3_SECRET_ACCESS_KEY_SECRET \
  REDIS_PASSWORD_SECRET TLS_CERT_SECRET TLS_KEY_SECRET UPTIME_PUSH_URL_SECRET; do
  require_value "$name_var"
done

ensure_literal_secret() {
  local secret_name="$1" value_var="$2"
  if docker secret inspect "$secret_name" >/dev/null 2>&1; then
    return
  fi
  require_value "$value_var"
  printf '%s' "${!value_var}" | docker secret create "$secret_name" - >/dev/null
  echo "created Docker secret: $secret_name"
}

ensure_file_secret() {
  local secret_name="$1" path_var="$2" path="${!2:-}"
  if docker secret inspect "$secret_name" >/dev/null 2>&1; then
    return
  fi
  require_value "$path_var"
  [[ "$path" = /* ]] || path="$root/${path#./}"
  [[ -s "$path" ]] || { echo "secret source is missing or empty: $path" >&2; exit 1; }
  docker secret create "$secret_name" "$path" >/dev/null
  echo "created Docker secret: $secret_name"
}

for node in "$API_NODE" "$REDIS_NODE" "$INFERENCE_NODE"; do
  docker node inspect "$node" >/dev/null
done
docker node update --label-add overtone.api=true "$API_NODE" >/dev/null
docker node update --label-add overtone.redis=true "$REDIS_NODE" >/dev/null
docker node update --label-add overtone.inference=true "$INFERENCE_NODE" >/dev/null

ensure_literal_secret "$DATABASE_URL_SECRET" DATABASE_URL
ensure_literal_secret "$WORKER_DATABASE_URL_SECRET" WORKER_DATABASE_URL
ensure_literal_secret "$S3_ACCESS_KEY_ID_SECRET" S3_ACCESS_KEY_ID
ensure_literal_secret "$S3_SECRET_ACCESS_KEY_SECRET" S3_SECRET_ACCESS_KEY
ensure_literal_secret "$REDIS_PASSWORD_SECRET" REDIS_PASSWORD
ensure_file_secret "$TLS_CERT_SECRET" TLS_CERT_FILE
ensure_file_secret "$TLS_KEY_SECRET" TLS_KEY_FILE
ensure_literal_secret "$UPTIME_PUSH_URL_SECRET" UPTIME_PUSH_URL

export STACK_NAME GATEWAY_IMAGE FRONTEND_IMAGE BACKEND_IMAGE SWARM_CHECK_IMAGE
export PUBLIC_SERVER_NAME ADMIN_ALLOW_RULES HTTP_PORT HTTPS_PORT KUMA_PORT
export S3_ENDPOINT S3_REGION S3_BUCKET INFERENCE_GRPC_ADDRESS INFERENCE_GRPC_TLS
export INFERENCE_LLM_BACKEND INFERENCE_SPECIALTY SESSION_TTL_HOURS MAX_UPLOAD_BYTES
export MAX_AUDIO_PARTS FFMPEG_TIMEOUT_MS HTTP_UPLOAD_TIMEOUT_MS
export DATABASE_URL_SECRET WORKER_DATABASE_URL_SECRET S3_ACCESS_KEY_ID_SECRET
export S3_SECRET_ACCESS_KEY_SECRET REDIS_PASSWORD_SECRET TLS_CERT_SECRET TLS_KEY_SECRET
export UPTIME_PUSH_URL_SECRET

docker stack deploy --with-registry-auth --prune --detach=true \
  --compose-file "$root/swarm/stack.yml" "$STACK_NAME"
"$root/scripts/wait-stack.sh" "$STACK_NAME" "${DEPLOY_TIMEOUT_SECONDS:-300}"
if [[ "${SKIP_SMOKE:-false}" != true ]]; then
  "$root/scripts/smoke-test.sh"
fi
