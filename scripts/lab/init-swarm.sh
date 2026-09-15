#!/usr/bin/env bash
set -Eeuo pipefail

: "${MANAGER_SSH:?set MANAGER_SSH, for example ubuntu@10.10.10.11}"
: "${MANAGER_ADDR:?set the manager private IP visible to workers}"
: "${WORKER1_SSH:?set WORKER1_SSH}"
: "${WORKER2_SSH:?set WORKER2_SSH}"

ssh_options=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
for host in "$MANAGER_SSH" "$WORKER1_SSH" "$WORKER2_SSH"; do
  ssh "${ssh_options[@]}" "$host" 'docker version >/dev/null'
done

manager_state="$(ssh "${ssh_options[@]}" "$MANAGER_SSH" "docker info --format '{{.Swarm.LocalNodeState}}'")"
if [[ "$manager_state" == inactive ]]; then
  ssh "${ssh_options[@]}" "$MANAGER_SSH" docker swarm init --advertise-addr "$MANAGER_ADDR"
fi
join_token="$(ssh "${ssh_options[@]}" "$MANAGER_SSH" docker swarm join-token -q worker)"

for worker in "$WORKER1_SSH" "$WORKER2_SSH"; do
  state="$(ssh "${ssh_options[@]}" "$worker" "docker info --format '{{.Swarm.LocalNodeState}}'")"
  if [[ "$state" == inactive ]]; then
    ssh "${ssh_options[@]}" "$worker" docker swarm join --token "$join_token" "${MANAGER_ADDR}:2377"
  fi
done

ssh "${ssh_options[@]}" "$MANAGER_SSH" docker node ls
echo "three-node Swarm initialized; no host packages were installed"

