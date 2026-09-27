#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$root/scripts/lib.sh"
load_env
require_command docker
require_registry_config
overtone_dir="${OVERTONE_DIR:-$root/../overtone}"
frontend_revision="${FRONTEND_REVISION:-$(component_revision "$overtone_dir" frontend)}"
backend_revision="${BACKEND_REVISION:-$(component_revision "$overtone_dir" backend)}"
gateway_revision="${GATEWAY_REVISION:-$(component_revision "$root" nginx)}"
swarm_check_revision="${SWARM_CHECK_REVISION:-$(component_revision "$root" swarm-check scripts/swarm-check.sh)}"

registry_prefix="$REGISTRY_HOST/$REGISTRY_USERNAME"
gateway_image="$registry_prefix/overtone-gateway:$gateway_revision"
frontend_image="$registry_prefix/overtone-frontend:$frontend_revision"
backend_image="$registry_prefix/overtone-backend:$backend_revision"
swarm_check_image="$registry_prefix/overtone-swarm-check:$swarm_check_revision"
require_distinct_image_versions "$gateway_image" "$frontend_image" "$backend_image" "$swarm_check_image"

docker buildx build --load --file "$overtone_dir/frontend/Dockerfile" \
  --build-arg "APP_VERSION=$frontend_revision" --tag "$frontend_image" "$overtone_dir/frontend"
docker buildx build --load --file "$overtone_dir/backend/Dockerfile" --target backend \
  --build-arg "APP_VERSION=$backend_revision" --build-arg "BEGET_CA_REFRESH=$(date +%s)" \
  --tag "$backend_image" "$overtone_dir/backend"
docker buildx build --load --file "$root/nginx/Dockerfile" --build-arg "APP_VERSION=$gateway_revision" \
  --tag "$gateway_image" "$root"
docker buildx build --load --platform linux/amd64 --file "$root/swarm-check/Dockerfile" \
  --build-arg "APP_VERSION=$swarm_check_revision" \
  --tag "$swarm_check_image" "$root"

GATEWAY_REF="$gateway_image" FRONTEND_REF="$frontend_image" BACKEND_REF="$backend_image" \
  SWARM_CHECK_REF="$swarm_check_image" \
  docker stack config --compose-file "$root/swarm/images.template.yml" > "$root/swarm/images.yml"
