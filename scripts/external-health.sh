#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$root/scripts/lib.sh"
load_env
compose=(docker compose --env-file "${ENV_FILE:-$root/.env}" -f "$root/external-local/compose.yml")

"${compose[@]}" exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"
curl --fail --silent --show-error "http://127.0.0.1:${S3_PORT}/minio/health/ready" >/dev/null
"${compose[@]}" run --rm minio-init >/dev/null
echo "external PostgreSQL and MinIO are healthy; bucket $S3_BUCKET exists"

