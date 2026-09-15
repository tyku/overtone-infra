#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$root/scripts/lib.sh"
load_env
component="${1:-all}"

case "$component" in
  backend) services=(api worker) ;;
  frontend) services=(frontend) ;;
  gateway) services=(gateway) ;;
  all) services=(gateway frontend api worker redis uptime-kuma swarm-check) ;;
  *) echo "usage: rollback.sh [backend|frontend|gateway|all]" >&2; exit 2 ;;
esac

for service in "${services[@]}"; do
  echo "rolling back ${STACK_NAME}_${service}"
  docker service rollback --detach=false "${STACK_NAME}_${service}"
done
"$root/scripts/wait-stack.sh" "$STACK_NAME" "${DEPLOY_TIMEOUT_SECONDS:-300}"
"$root/scripts/smoke-test.sh"

