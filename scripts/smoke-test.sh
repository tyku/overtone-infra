#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$root/scripts/lib.sh"
load_env
require_command curl

base_url="${BASE_URL:-https://${PUBLIC_SERVER_NAME}:${HTTPS_PORT}}"
curl_args=(--fail --silent --show-error --location --max-time 20 \
  --retry 12 --retry-delay 5 --retry-connrefused --retry-all-errors)
if [[ "${TLS_INSECURE:-false}" == true ]]; then
  curl_args+=(-k)
fi

gateway_health="$(curl "${curl_args[@]}" "$base_url/nginx-health")"
[[ "$gateway_health" == ok ]] || { echo "unexpected gateway health: $gateway_health" >&2; exit 1; }

api_headers="$(mktemp)"
trap 'rm -f "$api_headers"' EXIT
curl "${curl_args[@]}" --dump-header "$api_headers" --output /dev/null "$base_url/api/health"
grep -Eiq '^x-overtone-api-version: 1\r?$' "$api_headers"

index="$(curl "${curl_args[@]}" "$base_url/")"
grep -Eqi '<div[^>]+id="root"|<title>' <<<"$index"

status="$(curl "${curl_args[@]}" --no-fail --output /dev/null --write-out '%{http_code}' "$base_url/admin/not-a-route")"
[[ "$status" == 404 ]] || { echo "expected /admin/* to return 404, got $status" >&2; exit 1; }
echo "smoke passed: gateway, frontend, API and admin route policy"
