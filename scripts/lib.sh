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

require_immutable_image() {
  local name="$1" value="${!1:-}"
  require_value "$name"
  if [[ "$value" == *:latest ]] || ! [[ "$value" =~ (@sha256:[0-9a-f]{64}|:[0-9a-f]{7,40})$ ]]; then
    echo "$name must use an independent 7-40 character hex version tag or sha256 digest: $value" >&2
    return 1
  fi
}

require_distinct_image_versions() {
  local names=("$@") identities=() name value identity index
  for name in "${names[@]}"; do
    value="${!name:-}"
    if [[ "$value" == *@sha256:* ]]; then
      identity="${value##*@sha256:}"
    else
      identity="${value##*:}"
    fi
    for index in "${!identities[@]}"; do
      if [[ "${identities[$index]}" == "$identity" ]]; then
        echo "$name and ${names[$index]} share image version $identity; every image must be versioned independently" >&2
        return 1
      fi
    done
    identities+=("$identity")
  done
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
