#!/usr/bin/env bash
set -Eeuo pipefail

: "${MANAGER_SSH:?set MANAGER_SSH}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$root/scripts/lib.sh"
remote_dir="${REMOTE_INFRA_DIR:-/opt/overtone-infra}"
env_file="${ENV_FILE:-$root/.env}"
[[ -f "$env_file" ]] || { echo "missing $env_file" >&2; exit 1; }
load_env
require_registry_config
require_registry_images GATEWAY_IMAGE FRONTEND_IMAGE BACKEND_IMAGE SWARM_CHECK_IMAGE
: "${REGISTRY_PULL_TOKEN:?export REGISTRY_PULL_TOKEN; never store it in .env}"

printf '%s' "$REGISTRY_PULL_TOKEN" |
  ssh "$MANAGER_SSH" docker login "$REGISTRY_HOST" \
    --username "$REGISTRY_USERNAME" --password-stdin

ssh "$MANAGER_SSH" "sudo install -d -o \"\$USER\" -g \"\$(id -gn)\" '$remote_dir'"
rsync -az --delete --exclude .git --exclude .env --exclude local-certs \
  "$root/" "$MANAGER_SSH:$remote_dir/"
scp "$env_file" "$MANAGER_SSH:$remote_dir/.env"
if [[ -d "$root/local-certs" ]]; then
  rsync -az "$root/local-certs/" "$MANAGER_SSH:$remote_dir/local-certs/"
fi
ssh -t "$MANAGER_SSH" "cd '$remote_dir' && ./scripts/deploy.sh"
