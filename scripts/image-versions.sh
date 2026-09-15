#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$root/scripts/lib.sh"
overtone_dir="${OVERTONE_DIR:-$root/../overtone}"

printf 'frontend_version=%s\n' "$(component_revision "$overtone_dir" frontend)"
printf 'backend_version=%s\n' "$(component_revision "$overtone_dir" backend)"
printf 'gateway_version=%s\n' "$(component_revision "$root" nginx)"
printf 'swarm_check_version=%s\n' "$(component_revision "$root" swarm-check scripts/swarm-check.sh)"
