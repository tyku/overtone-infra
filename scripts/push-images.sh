#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$root/scripts/lib.sh"
load_env
require_command docker
require_registry_config
: "${REGISTRY_PUSH_TOKEN:?export REGISTRY_PUSH_TOKEN; never store it in .env}"

images=(GATEWAY_IMAGE FRONTEND_IMAGE BACKEND_IMAGE SWARM_CHECK_IMAGE)
require_registry_images "${images[@]}"
for image_var in "${images[@]}"; do
  require_immutable_image "$image_var"
done
require_distinct_image_versions "${images[@]}"

printf '%s' "$REGISTRY_PUSH_TOKEN" |
  docker login "$REGISTRY_HOST" --username "$REGISTRY_USERNAME" --password-stdin

for image_var in "${images[@]}"; do
  image="${!image_var}"
  echo "pushing $image"
  docker push "$image"
done
