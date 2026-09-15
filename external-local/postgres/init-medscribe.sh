#!/bin/sh
set -eu

# Runs only when PostgreSQL initializes an empty data directory.
psql --set=ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=medscribe_user="$MEDSCRIBE_DATABASE_USER" \
  --set=medscribe_password="$MEDSCRIBE_DATABASE_PASSWORD" \
  --set=medscribe_database="$MEDSCRIBE_DATABASE_NAME" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'medscribe_user', :'medscribe_password')
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = :'medscribe_user') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'medscribe_database', :'medscribe_user')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'medscribe_database') \gexec
SQL

