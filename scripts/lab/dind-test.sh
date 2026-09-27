#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$root/scripts/lib.sh"
lab_compose=(docker compose -f "$root/scripts/lab/dind-compose.yml")
external_compose=(docker compose -f "$root/external-local/compose.yml" -f "$root/scripts/lab/external-dind.override.yml" --profile inference)
frontend_revision="$(component_revision "$root/../overtone" frontend)"
backend_revision="$(component_revision "$root/../overtone" backend)"
gateway_revision="$(component_revision "$root" nginx)"
swarm_check_revision="$(component_revision "$root" swarm-check scripts/swarm-check.sh)"

export POSTGRES_USER=overtone POSTGRES_PASSWORD=dind_postgres_password POSTGRES_DB=overtone
export MEDSCRIBE_DATABASE_USER=medscribe MEDSCRIBE_DATABASE_PASSWORD=dind_medscribe_password MEDSCRIBE_DATABASE_NAME=medscribe
export MINIO_ROOT_USER=dindminio MINIO_ROOT_PASSWORD=dind_minio_password_123 S3_BUCKET=medical-scribe S3_REGION=us-east-1
export S3_ACCESS_KEY_ID=dindapp S3_SECRET_ACCESS_KEY=dind_app_password_123
export POSTGRES_PORT=25432 S3_PORT=29000 S3_CONSOLE_PORT=29001
export POSTGRES_VOLUME_NAME=overtone_dind_external_postgres_v1 MINIO_VOLUME_NAME=overtone_dind_external_minio_v1
export MEDICAL_SCRIBE_DIR=../../medical-scribe INFERENCE_PORT=25051
image_archive=""

cleanup_containers() {
  [[ -z "$image_archive" ]] || rm -f "$image_archive"
  docker exec overtone-dind-lab-worker-1-1 docker swarm leave >/dev/null 2>&1 || true
  docker exec overtone-dind-lab-worker-2-1 docker swarm leave >/dev/null 2>&1 || true
  docker exec overtone-dind-lab-manager-1-1 docker swarm leave --force >/dev/null 2>&1 || true
  "${external_compose[@]}" down >/dev/null 2>&1 || true
  "${lab_compose[@]}" down >/dev/null 2>&1 || true
}
trap cleanup_containers EXIT

"${lab_compose[@]}" up -d --wait
"${external_compose[@]}" up -d --wait postgres minio minio-init inference-mock

manager=(docker exec overtone-dind-lab-manager-1-1 docker)
worker1=(docker exec overtone-dind-lab-worker-1-1 docker)
worker2=(docker exec overtone-dind-lab-worker-2-1 docker)
if [[ "$("${manager[@]}" info --format '{{.Swarm.LocalNodeState}}')" == inactive ]]; then
  "${manager[@]}" swarm init --advertise-addr 172.30.30.21 >/dev/null
fi
token="$("${manager[@]}" swarm join-token -q worker)"
if [[ "$("${worker1[@]}" info --format '{{.Swarm.LocalNodeState}}')" == inactive ]]; then
  "${worker1[@]}" swarm join --token "$token" 172.30.30.21:2377 >/dev/null
fi
if [[ "$("${worker2[@]}" info --format '{{.Swarm.LocalNodeState}}')" == inactive ]]; then
  "${worker2[@]}" swarm join --token "$token" 172.30.30.21:2377 >/dev/null
fi

gateway_ref="overtone-gateway:${gateway_revision}"
check_ref="overtone-swarm-check:${swarm_check_revision}"
frontend_ref="overtone-frontend:${frontend_revision}"
backend_ref="overtone-backend:${backend_revision}"

docker build --build-arg "APP_VERSION=$gateway_revision" -f "$root/nginx/Dockerfile" -t "$gateway_ref" "$root"
docker build --build-arg "APP_VERSION=$swarm_check_revision" -f "$root/swarm-check/Dockerfile" -t "$check_ref" "$root"
docker buildx build --load -f "$root/../overtone/frontend/Dockerfile" \
  --build-arg "APP_VERSION=$frontend_revision" -t "$frontend_ref" "$root/../overtone/frontend"
docker build --target backend --build-arg "APP_VERSION=$backend_revision" -f "$root/../overtone/backend/Dockerfile" \
  -t "$backend_ref" "$root/../overtone/backend"

image_archive="$(mktemp)"
docker save -o "$image_archive" "$gateway_ref" "$check_ref" "$frontend_ref" "$backend_ref"
for daemon in overtone-dind-lab-manager-1-1 overtone-dind-lab-worker-1-1 overtone-dind-lab-worker-2-1; do
  docker exec -i "$daemon" docker load < "$image_archive" >/dev/null
done
rm -f "$image_archive"
image_archive=""

stage="$(mktemp -d)"
cp -R "$root" "$stage/infra"
GATEWAY_REF="$gateway_ref" FRONTEND_REF="$frontend_ref" BACKEND_REF="$backend_ref" \
  SWARM_CHECK_REF="$check_ref" \
  docker stack config --compose-file "$root/swarm/images.template.yml" > "$stage/infra/swarm/images.yml"
mkdir -p "$stage/infra/local-certs"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -keyout "$stage/infra/local-certs/tls.key" -out "$stage/infra/local-certs/tls.crt" \
  -subj /CN=localhost -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' >/dev/null 2>&1
cat > "$stage/infra/.env" <<EOF
STACK_NAME=overtone
STACK_RESOLVE_IMAGE=never
PUBLIC_SERVER_NAME=localhost
ADMIN_SERVER_NAME=localhost
ADMIN_BASTION_CIDR=127.0.0.1/32
HTTP_PORT=80
HTTPS_PORT=443
KUMA_PORT=3001
S3_ENDPOINT=http://172.30.30.11:9000
S3_REGION=us-east-1
S3_BUCKET=medical-scribe
INFERENCE_GRPC_ADDRESS=172.30.30.12:50051
INFERENCE_GRPC_TLS=false
INFERENCE_LLM_BACKEND=LOCAL
INFERENCE_SPECIALTY=
API_NODE=worker-1
REDIS_NODE=worker-1
INFERENCE_NODE=worker-2
DATABASE_URL_SECRET=overtone_database_url_dind_v1
WORKER_DATABASE_URL_SECRET=overtone_worker_database_url_dind_v1
S3_ACCESS_KEY_ID_SECRET=overtone_s3_access_key_id_dind_v1
S3_SECRET_ACCESS_KEY_SECRET=overtone_s3_secret_access_key_dind_v1
REDIS_PASSWORD_SECRET=overtone_redis_password_dind_v1
TLS_CERT_SECRET=overtone_tls_cert_dind_v1
TLS_KEY_SECRET=overtone_tls_key_dind_v1
UPTIME_PUSH_URL_SECRET=overtone_uptime_push_url_dind_v1
DATABASE_URL=postgresql://overtone:dind_postgres_password@172.30.30.10:5432/overtone
WORKER_DATABASE_URL=postgresql://overtone:dind_postgres_password@172.30.30.10:5432/overtone
S3_ACCESS_KEY_ID=dindapp
S3_SECRET_ACCESS_KEY=dind_app_password_123
REDIS_PASSWORD=dind_redis_password
TLS_CERT_FILE=./local-certs/tls.crt
TLS_KEY_FILE=./local-certs/tls.key
UPTIME_PUSH_URL=http://uptime-kuma:3001/api/push/not-configured
SESSION_TTL_HOURS=12
MAX_UPLOAD_BYTES=1073741824
MAX_AUDIO_PARTS=1000
FFMPEG_TIMEOUT_MS=1800000
HTTP_UPLOAD_TIMEOUT_MS=2100000
EOF
docker cp "$stage/infra/." overtone-dind-lab-manager-1-1:/infra
rm -rf "$stage"

docker exec -w /infra overtone-dind-lab-manager-1-1 ./scripts/deploy.sh
if [[ "${RUN_FAULT_TESTS:-true}" == true ]]; then
  docker exec -w /infra overtone-dind-lab-manager-1-1 ./scripts/fault-test.sh
fi
BASE_URL=https://127.0.0.1:18443 \
  bash -c 'args=(-kfsS --retry 12 --retry-delay 5 --retry-connrefused --retry-all-errors); curl "${args[@]}" "$BASE_URL/nginx-health" | grep -qx ok; curl "${args[@]}" "$BASE_URL/api/health" >/dev/null; curl "${args[@]}" "$BASE_URL/" | grep -qi "<div.*id=\"root\"\|<title>"'

for expected in gateway=2 frontend=2 api=1 worker=1 redis=1 uptime-kuma=1 swarm-check=1; do
  service="${expected%%=*}"
  wanted="${expected#*=}"
  replicas="$("${manager[@]}" service ls --filter "name=overtone_${service}" --format '{{.Replicas}}')"
  replicas="${replicas%% *}"
  [[ "$replicas" == "$wanted/$wanted" ]] || { "${manager[@]}" service ps --no-trunc "overtone_${service}"; exit 1; }
done
"${manager[@]}" node ls
"${manager[@]}" stack services overtone
echo "three-daemon Swarm integration test passed; lab containers stopped, volumes preserved"
