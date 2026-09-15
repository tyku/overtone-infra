#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$root/scripts/lib.sh"
load_env
require_command docker
overtone_dir="${OVERTONE_DIR:-$root/../overtone}"
revision="${BUILD_REVISION:-$(git -C "$overtone_dir" rev-parse HEAD)}"

docker buildx build --load --file "$overtone_dir/frontend/Dockerfile" \
  --build-arg "APP_VERSION=$revision" --tag "$FRONTEND_IMAGE" "$overtone_dir/frontend"
docker buildx build --load --file "$overtone_dir/backend/Dockerfile" --target backend \
  --build-arg "APP_VERSION=$revision" --tag "$BACKEND_IMAGE" "$overtone_dir/backend"
docker buildx build --load --file "$root/nginx/Dockerfile" --build-arg "APP_VERSION=$revision" \
  --tag "$GATEWAY_IMAGE" "$root"
docker buildx build --load --file "$root/swarm-check/Dockerfile" \
  --tag "$SWARM_CHECK_IMAGE" "$root"
