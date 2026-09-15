#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$root/scripts/lib.sh"
load_env
require_command docker

stack="$STACK_NAME"
stateful_node="${FAULT_NODE:-$API_NODE}"

echo "forcing an API task restart"
before="$(docker service ps --filter desired-state=running --format '{{.ID}}' "${stack}_api" | head -n 1)"
docker service update --force --detach=false "${stack}_api" >/dev/null
"$root/scripts/wait-stack.sh" "$stack" 180
after="$(docker service ps --filter desired-state=running --format '{{.ID}}' "${stack}_api" | head -n 1)"
[[ -n "$before" && -n "$after" && "$before" != "$after" ]]

echo "forcing a worker task restart"
worker_before="$(docker service ps --filter desired-state=running --format '{{.ID}}' "${stack}_worker" | head -n 1)"
docker service update --force --detach=false "${stack}_worker" >/dev/null
"$root/scripts/wait-stack.sh" "$stack" 180
worker_after="$(docker service ps --filter desired-state=running --format '{{.ID}}' "${stack}_worker" | head -n 1)"
[[ -n "$worker_before" && -n "$worker_after" && "$worker_before" != "$worker_after" ]]

echo "testing a one-at-a-time frontend rolling update and rollback"
docker service update --force --detach=false "${stack}_frontend" >/dev/null
"$root/scripts/wait-stack.sh" "$stack" 180
docker service rollback --detach=false "${stack}_frontend" >/dev/null
"$root/scripts/wait-stack.sh" "$stack" 180

echo "draining persistent node $stateful_node; API/Redis are expected to stop, not move their local volumes"
restore_node() {
  docker node update --availability active "$stateful_node" >/dev/null 2>&1 || true
}
trap restore_node EXIT
docker node update --availability drain "$stateful_node" >/dev/null
deadline=$((SECONDS + 120))
while (( SECONDS < deadline )); do
  api_replicas="$(docker service ls --filter "name=${stack}_api" --format '{{.Replicas}}')"
  redis_replicas="$(docker service ls --filter "name=${stack}_redis" --format '{{.Replicas}}')"
  if [[ "$api_replicas" == 0/1 && "$redis_replicas" == 0/1 ]]; then
    break
  fi
  sleep 3
done
[[ "${api_replicas:-}" == 0/1 && "${redis_replicas:-}" == 0/1 ]]
restore_node
trap - EXIT
"$root/scripts/wait-stack.sh" "$stack" 300
if [[ "${SKIP_SMOKE:-false}" != true ]]; then
  "$root/scripts/smoke-test.sh"
fi
echo "fault tests passed: restart, rolling update, rollback and stateful-node recovery"
