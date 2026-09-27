#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$root/scripts/lib.sh"
load_env

job="${STACK_NAME}_alert-test"
swarm_check_image="$(docker service inspect --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' "${STACK_NAME}_swarm-check")"
docker service rm "$job" >/dev/null 2>&1 || true
docker service create --quiet --name "$job" --mode replicated-job --replicas 1 \
  --constraint node.role==manager \
  --network "${STACK_NAME}_monitoring" \
  --secret "source=${UPTIME_PUSH_URL_SECRET},target=uptime_push_url" \
  --env "STACK_NAME=${STACK_NAME}" \
  --env 'EXPECTED_SERVICES=intentional-test-service=1' \
  --entrypoint /usr/local/bin/swarm-check \
  "$swarm_check_image" >/dev/null

deadline=$((SECONDS + 90))
while (( SECONDS < deadline )); do
  state="$(docker service ps --format '{{.CurrentState}}' "$job" | head -n 1)"
  if [[ "$state" == Complete* ]]; then
    break
  fi
  if [[ "$state" == Failed* || "$state" == Rejected* ]]; then
    docker service ps --no-trunc "$job" >&2
    exit 1
  fi
  sleep 2
done
docker service logs "$job" || true
docker service rm "$job" >/dev/null
echo "a deliberate DOWN push was sent; the regular swarm-check sends recovery within 60 seconds"
