#!/usr/bin/env bash
set -Eeuo pipefail

: "${MANAGER_SSH:?set MANAGER_SSH}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
remote_dir="${REMOTE_INFRA_DIR:-/opt/overtone-infra}"
env_file="${ENV_FILE:-$root/.env}"
[[ -f "$env_file" ]] || { echo "missing $env_file" >&2; exit 1; }

ssh "$MANAGER_SSH" "sudo install -d -o \"\$USER\" -g \"\$(id -gn)\" '$remote_dir'"
rsync -az --delete --exclude .git --exclude .env --exclude local-certs \
  "$root/" "$MANAGER_SSH:$remote_dir/"
scp "$env_file" "$MANAGER_SSH:$remote_dir/.env"
if [[ -d "$root/local-certs" ]]; then
  rsync -az "$root/local-certs/" "$MANAGER_SSH:$remote_dir/local-certs/"
fi
ssh -t "$MANAGER_SSH" "cd '$remote_dir' && ./scripts/deploy.sh"

