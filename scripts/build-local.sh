#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$root/scripts/lib.sh"
load_env
require_command docker
overtone_dir="${OVERTONE_DIR:-$root/../overtone}"
frontend_revision="${FRONTEND_REVISION:-$(component_revision "$overtone_dir" frontend)}"
backend_revision="${BACKEND_REVISION:-$(component_revision "$overtone_dir" backend)}"
gateway_revision="${GATEWAY_REVISION:-$(component_revision "$root" nginx)}"
swarm_check_revision="${SWARM_CHECK_REVISION:-$(component_revision "$root" swarm-check scripts/swarm-check.sh)}"

for image_var in GATEWAY_IMAGE FRONTEND_IMAGE BACKEND_IMAGE SWARM_CHECK_IMAGE; do
  require_immutable_image "$image_var"
done
require_distinct_image_versions GATEWAY_IMAGE FRONTEND_IMAGE BACKEND_IMAGE SWARM_CHECK_IMAGE

docker buildx build --load --file "$overtone_dir/frontend/Dockerfile" \
  --build-arg "APP_VERSION=$frontend_revision" --tag "$FRONTEND_IMAGE" "$overtone_dir/frontend"
docker buildx build --load --file "$overtone_dir/backend/Dockerfile" --target backend \
  --build-arg "APP_VERSION=$backend_revision" --tag "$BACKEND_IMAGE" "$overtone_dir/backend"
docker buildx build --load --file "$root/nginx/Dockerfile" --build-arg "APP_VERSION=$gateway_revision" \
  --tag "$GATEWAY_IMAGE" "$root"
docker buildx build --load --file "$root/swarm-check/Dockerfile" \
  --build-arg "APP_VERSION=$swarm_check_revision" \
  --tag "$SWARM_CHECK_IMAGE" "$root"
