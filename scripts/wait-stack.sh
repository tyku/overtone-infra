#!/usr/bin/env bash
set -Eeuo pipefail

stack_name="${1:?usage: wait-stack.sh STACK [TIMEOUT_SECONDS]}"
timeout_seconds="${2:-300}"
deadline=$((SECONDS + timeout_seconds))
expected=(gateway=2 frontend=2 api=1 worker=1 redis=1 uptime-kuma=1 swarm-check=1)

while (( SECONDS < deadline )); do
  all_ready=true
  for item in "${expected[@]}"; do
    service="${item%%=*}"
    wanted="${item#*=}"
    replicas="$(docker service ls --filter "name=${stack_name}_${service}" --format '{{.Replicas}}' | head -n 1)"
    replicas="${replicas%% *}"
    if [[ "$replicas" != "$wanted/$wanted" ]]; then
      all_ready=false
      break
    fi
  done
  if [[ "$all_ready" == true ]]; then
    echo "stack $stack_name is ready"
    exit 0
  fi
  sleep 5
done

docker stack services "$stack_name" >&2 || true
for item in "${expected[@]}"; do
  docker service ps --no-trunc "${stack_name}_${item%%=*}" >&2 || true
done
echo "stack $stack_name did not converge in ${timeout_seconds}s" >&2
exit 1
