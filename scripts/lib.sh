#!/usr/bin/env bash
set -Eeuo pipefail

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

load_env() {
  local root env_file
  root="$(repo_root)"
  env_file="${ENV_FILE:-$root/.env}"
  if [[ ! -f "$env_file" ]]; then
    echo "missing env file: $env_file (copy .env.example)" >&2
    return 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || { echo "required command not found: $1" >&2; return 1; }
}

require_value() {
  local name="$1"
  [[ -n "${!name:-}" ]] || { echo "required variable is empty: $name" >&2; return 1; }
  [[ "${!name}" != *change_me* ]] || { echo "replace placeholder in variable: $name" >&2; return 1; }
}

require_registry_config() {
  require_value REGISTRY_HOST
  require_value REGISTRY_USERNAME
  [[ "$REGISTRY_HOST" =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || {
    echo "REGISTRY_HOST must be a registry hostname with an optional port: $REGISTRY_HOST" >&2
    return 1
  }
  [[ "$REGISTRY_USERNAME" =~ ^[A-Za-z0-9_.-]+$ ]] || {
    echo "REGISTRY_USERNAME contains unsupported characters" >&2
    return 1
  }
}

require_registry_image_refs() {
  local value
  for value in "$@"; do
    [[ "$value" == "$REGISTRY_HOST/"* ]] || {
      echo "image must use configured registry $REGISTRY_HOST: $value" >&2
      return 1
    }
  done
}

require_immutable_image_ref() {
  local value="$1"
  if [[ "$value" == *:latest ]] || ! [[ "$value" =~ (@sha256:[0-9a-f]{64}|:[0-9a-f]{7,40})$ ]]; then
    echo "image must use an independent 7-40 character hex version tag or sha256 digest: $value" >&2
    return 1
  fi
}

require_distinct_image_versions() {
  local values=("$@") identities=() value identity index
  for value in "${values[@]}"; do
    if [[ "$value" == *@sha256:* ]]; then
      identity="${value##*@sha256:}"
    else
      identity="${value##*:}"
    fi
    for index in "${!identities[@]}"; do
      if [[ "${identities[$index]}" == "$identity" ]]; then
        echo "$value and ${values[$index]} share image version $identity; every image must be versioned independently" >&2
        return 1
      fi
    done
    identities+=("$identity")
  done
}

image_manifest_refs() {
  local manifest="$1"
  [[ -s "$manifest" ]] || { echo "missing or empty image manifest: $manifest" >&2; return 1; }
  docker compose -f "$manifest" config --images
}

validate_image_manifest() {
  local manifest="$1" output unique_output services image api_image worker_image
  local -a refs=() unique_refs=()
  services="$(docker compose -f "$manifest" config --services | LC_ALL=C sort)" || return 1
  [[ "$services" == $'api\nfrontend\ngateway\nswarm-check\nworker' ]] || {
    echo "image manifest must define only api, frontend, gateway, swarm-check and worker" >&2
    return 1
  }
  api_image="$(docker compose -f "$manifest" config --images api)" || return 1
  worker_image="$(docker compose -f "$manifest" config --images worker)" || return 1
  [[ "$api_image" == "$worker_image" ]] || {
    echo "api and worker must use the same backend image" >&2
    return 1
  }
  output="$(image_manifest_refs "$manifest")" || return 1
  while IFS= read -r image; do refs+=("$image"); done <<< "$output"
  (( ${#refs[@]} == 5 )) || { echo "image manifest must define five service images" >&2; return 1; }
  unique_output="$(printf '%s\n' "${refs[@]}" | LC_ALL=C sort -u)"
  while IFS= read -r image; do unique_refs+=("$image"); done <<< "$unique_output"
  (( ${#unique_refs[@]} == 4 )) || { echo "image manifest must contain four distinct images" >&2; return 1; }
  for image in "${unique_refs[@]}"; do
    require_immutable_image_ref "$image" || return 1
  done
  require_distinct_image_versions "${unique_refs[@]}"
}

component_revision() {
  local base="${1:?component_revision BASE PATH...}"
  shift
  (( $# > 0 )) || { echo "component_revision requires at least one path" >&2; return 1; }
  (
    cd "$base"
    git ls-files --cached --others --exclude-standard -- "$@" |
      LC_ALL=C sort -u |
      while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        printf '%s %s\n' "$file" "$(git hash-object "$file")"
      done
  ) | git hash-object --stdin
}
