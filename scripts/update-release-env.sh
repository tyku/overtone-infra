#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 5 )); then
  echo 'usage: update-release-env.sh DOCKERHUB_USERNAME BACKEND_DIGEST FRONTEND_DIGEST GATEWAY_DIGEST SWARM_CHECK_DIGEST' >&2
  exit 2
fi

username="$1"
[[ "$username" =~ ^[A-Za-z0-9_.-]+$ ]] || {
  echo 'invalid Docker Hub username' >&2
  exit 1
}
for digest in "${@:2}"; do
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    echo 'invalid image digest' >&2
    exit 1
  }
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$root/.env"
[[ -f "$env_file" && ! -L "$env_file" && -O "$env_file" && -r "$env_file" && -w "$env_file" ]] || {
  echo 'manager .env must already exist and be owned by the deploy user' >&2
  exit 1
}
env_mode="$(stat -c %a "$env_file" 2>/dev/null || stat -f %Lp "$env_file")"
[[ "$env_mode" == 600 ]] || {
  echo 'manager .env must have mode 0600' >&2
  exit 1
}

registry_host=docker.io
registry_username="$username"
backend_image="docker.io/$username/overtone-backend@$2"
frontend_image="docker.io/$username/overtone-frontend@$3"
gateway_image="docker.io/$username/overtone-gateway@$4"
swarm_check_image="docker.io/$username/overtone-swarm-check@$5"

umask 077
temporary_env="$(mktemp "$root/.env.release.XXXXXX")"
trap 'rm -f -- "$temporary_env"' EXIT

seen_keys=' '
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    REGISTRY_HOST=*) line="REGISTRY_HOST=$registry_host"; seen_keys+='REGISTRY_HOST ' ;;
    REGISTRY_USERNAME=*) line="REGISTRY_USERNAME=$registry_username"; seen_keys+='REGISTRY_USERNAME ' ;;
    BACKEND_IMAGE=*) line="BACKEND_IMAGE=$backend_image"; seen_keys+='BACKEND_IMAGE ' ;;
    FRONTEND_IMAGE=*) line="FRONTEND_IMAGE=$frontend_image"; seen_keys+='FRONTEND_IMAGE ' ;;
    GATEWAY_IMAGE=*) line="GATEWAY_IMAGE=$gateway_image"; seen_keys+='GATEWAY_IMAGE ' ;;
    SWARM_CHECK_IMAGE=*) line="SWARM_CHECK_IMAGE=$swarm_check_image"; seen_keys+='SWARM_CHECK_IMAGE ' ;;
  esac
  printf '%s\n' "$line" >> "$temporary_env"
done < "$env_file"

for entry in \
  "REGISTRY_HOST=$registry_host" \
  "REGISTRY_USERNAME=$registry_username" \
  "BACKEND_IMAGE=$backend_image" \
  "FRONTEND_IMAGE=$frontend_image" \
  "GATEWAY_IMAGE=$gateway_image" \
  "SWARM_CHECK_IMAGE=$swarm_check_image"; do
  key="${entry%%=*}"
  [[ "$seen_keys" == *" $key "* ]] || printf '%s\n' "$entry" >> "$temporary_env"
done

chmod 0600 "$temporary_env"
mv -f -- "$temporary_env" "$env_file"
echo 'updated manager image references'
