#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$root/scripts/lib.sh"
load_env
require_command docker
require_registry_config
: "${REGISTRY_PUSH_TOKEN:?export REGISTRY_PUSH_TOKEN; never store it in .env}"

validate_image_manifest "$root/swarm/images.yml"
images="$(image_manifest_refs "$root/swarm/images.yml" | LC_ALL=C sort -u)"
while IFS= read -r image; do
  require_registry_image_refs "$image"
done <<< "$images"

printf '%s' "$REGISTRY_PUSH_TOKEN" |
  docker login "$REGISTRY_HOST" --username "$REGISTRY_USERNAME" --password-stdin

while IFS= read -r image; do
  echo "pushing $image"
  docker push "$image"
done <<< "$images"
