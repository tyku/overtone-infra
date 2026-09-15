#!/bin/sh
set -eu

read_secret() {
  secret_path="/run/secrets/$1"
  if [ ! -s "$secret_path" ]; then
    echo "required secret is missing: $1" >&2
    exit 1
  fi
  tr -d '\r\n' < "$secret_path"
}

mode="${1:-api}"
if [ "$mode" = worker ]; then
  DATABASE_URL="$(read_secret worker_database_url)"
else
  DATABASE_URL="$(read_secret database_url)"
fi
export DATABASE_URL
export S3_ACCESS_KEY_ID="$(read_secret s3_access_key_id)"
export S3_SECRET_ACCESS_KEY="$(read_secret s3_secret_access_key)"
export REDIS_PASSWORD="$(read_secret redis_password)"

if [ "$mode" = worker ]; then
  exec node dist/worker/main.js
fi
exec node dist/main.js

