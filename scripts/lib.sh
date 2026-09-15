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
    echo "$name must use a Git SHA tag or sha256 digest: $value" >&2
    return 1
  fi
}

