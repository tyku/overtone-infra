#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for script in "$root"/scripts/*.sh "$root"/scripts/lab/*.sh \
  "$root"/external-local/postgres/*.sh "$root"/external-local/minio/*.sh; do
  bash -n "$script"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$root"/scripts/*.sh "$root"/scripts/lab/*.sh
fi

env_file="$(mktemp)"
trap 'rm -f "$env_file"' EXIT
sed \
  -e 's/change_me/local_validation_secret/g' \
  "$root/.env.example" > "$env_file"

docker compose --env-file "$env_file" -f "$root/external-local/compose.yml" config --quiet
set -a
# shellcheck disable=SC1090
source "$env_file"
set +a
docker stack config --compose-file "$root/swarm/stack.yml" >/dev/null
echo "validation passed: shell, external Compose and Swarm stack"
