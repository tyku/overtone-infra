#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-$root/local-certs}"
mkdir -p "$output_dir"
if [[ -e "$output_dir/tls.crt" || -e "$output_dir/tls.key" ]]; then
  echo "refusing to overwrite existing certificate files in $output_dir" >&2
  exit 1
fi
openssl req -x509 -newkey rsa:3072 -nodes -days 30 \
  -keyout "$output_dir/tls.key" -out "$output_dir/tls.crt" \
  -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1'
chmod 0600 "$output_dir/tls.key"
echo "created a 30-day local-only certificate in $output_dir"

