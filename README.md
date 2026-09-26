# Overtone infrastructure

Production-shaped Docker Swarm infrastructure for Overtone. PostgreSQL, S3 and medical-scribe are external dependencies by design; the local lab substitutes Docker PostgreSQL, MinIO and an optional medical-scribe mock without adding them to the Swarm stack. Local MinIO uses separate root and application credentials and attaches a bucket-scoped policy to the application user.

## Architecture

```text
Internet -> TLS Nginx gateway (2) -> frontend runtime (2)
                               \-> API (1, fixed worker + recordings volume)
                                      |-> PostgreSQL (external)
                                      |-> S3/MinIO (external)
                                      `-> Redis (1, fixed worker + AOF volume)

worker (1, tunnel worker) -> Redis/PostgreSQL/S3
                           -> private worker IP:15051
                              <- reverse SSH <- medical-scribe GPU:50051

manager -> Uptime Kuma (1) <- push status from swarm-check (1)
```

The single manager is an explicit demo availability compromise. Gateway and frontend use one replica per worker. Overlay traffic on application/monitoring networks is encrypted. No application service publishes a bypass port around the gateway.

The frontend image is built and owned by `../overtone/frontend`: its internal unprivileged Nginx serves immutable application assets on port 8080. In Swarm it runs with a read-only root filesystem and a bounded `/tmp` tmpfs. This static origin is distinct from the infrastructure-owned TLS gateway.

The source audit is in [docs/AUDIT.md](docs/AUDIT.md).

## Repository contents

- `swarm/stack.yml` — Swarm services, placement, limits, healthchecks, rolling update/rollback.
- `external-local/compose.yml` — PostgreSQL, MinIO and optional inference mock outside Swarm.
- `nginx/` — dedicated TLS gateway image and admin CIDR policy.
- `../overtone/frontend/Dockerfile` owns the self-contained frontend image; this repository only configures its Swarm runtime.
- `swarm-check/` — lightweight manager-side Swarm/replica/restart/disk check.
- `scripts/` — deploy, rollback, smoke, fault and three-VM lab helpers.
- `systemd/` — resilient reverse SSH tunnel example for the GPU host.
- `.github/workflows/ci.yml` — infrastructure validation; release and rollback workflows live in the `overtone` code repository.

## Local three-VM test

Prerequisites: three Linux VMs with Docker Engine already installed, an authenticated remote registry reachable by the workstation and all nodes, `docker`, `ssh`, `rsync`, `curl`, and `openssl` on the workstation. The lab never starts an ad-hoc registry or enables insecure-registry mode. VM/network details are in [docs/VM-LAB.md](docs/VM-LAB.md).

```bash
cp .env.example .env
# Set strong local credentials, actual VM/external IPs and node hostnames.
# Set REGISTRY_HOST/REGISTRY_USERNAME and remote-registry image references.
# Run `make versions`, then give every image its own returned content version.

make cert
make external-up-inference
make external-health
make build

# Keep tokens out of .env. The push token needs package write permission.
export REGISTRY_PUSH_TOKEN=...
make push
unset REGISTRY_PUSH_TOKEN

export MANAGER_SSH=ubuntu@10.10.10.11 MANAGER_ADDR=10.10.10.11
export WORKER1_SSH=ubuntu@10.10.10.12 WORKER2_SSH=ubuntu@10.10.10.13
# A read-only package token is sufficient for manager/Swarm pulls.
export REGISTRY_PULL_TOKEN=...
./scripts/lab/init-swarm.sh
./scripts/lab/sync-and-deploy.sh
unset REGISTRY_PULL_TOKEN
```

`make versions` calculates four independent content versions from the exact files used by each image. Changing frontend source does not change the backend, gateway or swarm-check version. `make build` only builds into the current Docker daemon; `make push` authenticates to `REGISTRY_HOST` and pushes all four references. `sync-and-deploy.sh` authenticates the manager without copying the token into `.env`, and Swarm forwards that pull authorization to workers via `--with-registry-auth`. Deploy rejects `latest`, non-hex version tags and a version identifier shared by two images; registry digests are also accepted.

Run verification against the manager/load-balancer address:

```bash
BASE_URL=https://10.10.10.11 TLS_INSECURE=true make smoke
ssh -t "$MANAGER_SSH" 'cd /opt/overtone-infra && ./scripts/fault-test.sh'
ssh -t "$MANAGER_SSH" 'cd /opt/overtone-infra && ./scripts/uptime-alert-test.sh'
```

The fault suite forces an API restart, performs a one-at-a-time frontend rolling update, rolls it back, drains the stateful worker, verifies that local data does not migrate accidentally, restores the node and reruns smoke. It never removes volumes.

When VM tooling is unavailable, `make dind-test` exercises the same stack against three isolated privileged Docker daemons. It loads test images directly into those daemons and does not start a registry. This is useful CI-grade multi-node coverage, but it is not represented as a substitute for the final three-VM network/firewall test.

To stop only local external containers while preserving data:

```bash
make external-down
```

## Uptime Kuma

Open private manager port `3001`, create the admin account, then configure:

- HTTPS monitor for the public URL;
- HTTP keyword/status monitor for `/api/health`;
- Push monitor named `swarm-check`, with heartbeat interval slightly over 60 seconds;
- required notification channels.

Put the complete Push URL in `UPTIME_PUSH_URL`, bump `UPTIME_PUSH_URL_SECRET` to a new versioned name and redeploy. `make alert-test` emits an intentional DOWN result; the regular check emits recovery on its next interval. `swarm-check` checks node readiness/availability, desired replicas, failed gateway/API/worker tasks and manager disk usage. This intentionally replaces Prometheus/Grafana/Loki.

## Reverse SSH tunnel

Install `autossh` on the GPU machine only after explicit operator approval. Copy the systemd examples to `/etc/systemd/system/overtone-gpu-tunnel.service` and `/etc/overtone/gpu-tunnel.env`, provision a dedicated SSH key and pin the worker host key. The worker SSH server must allow `GatewayPorts clientspecified`; restrict the tunnel account and firewall port 15051 to the Swarm private network.

The GPU host opens:

```text
worker-private-ip:15051 -> reverse SSH -> GPU localhost:50051
```

Set `INFERENCE_GRPC_ADDRESS=worker-private-ip:15051`. Do not use worker loopback: an overlay-network container has a different network namespace.

## Deploy and rollback

`scripts/deploy.sh` must run on the manager. It labels selected workers, creates only missing external Docker Secrets, deploys with registry auth, waits for exact replica counts and runs smoke. Secret values are read from files/environment once and never placed in the service spec.

```bash
make deploy
make rollback COMPONENT=backend   # backend, frontend, gateway, or all
```

Docker Secrets are immutable. For rotation, create a new `*_v2` name in `.env` and deploy. Old secrets are retained until an operator explicitly removes them after verification.

## CI/CD

`ci.yml` in this repository validates shell and both deployment models and builds independently versioned infra images. Production `release.yml` and `rollback.yml` live in the `overtone` code repository. A push to its `main` branch builds and pushes the application and infrastructure images, but never deploys. Production deploy remains opt-in through `workflow_dispatch`, the `deploy` boolean, and the protected `production` environment.

Configure the `overtone` repository with variable `DOCKERHUB_USERNAME` and secrets `DOCKERHUB_TOKEN` for build/push and `OVERTONE_INFRA_REPO_TOKEN` for read-only checkout of this repository. Configure its `production` environment with variables `BASTION_HOST` (or a same-named secret), `BASTION_USER=overtone_deploy`, `MANAGER_PRIVATE_HOST` (or a same-named secret), and `DEPLOY_USER=overtone_deploy`; configure secrets `DEPLOY_SSH_KEY`, `DEPLOY_KNOWN_HOSTS`, `SWARM_ENV_FILE`, and `DOCKERHUB_TOKEN`. The environment `DOCKERHUB_TOKEN` must be a distinct pull-only credential and overrides the repository build/push token only in the deploy job. Rollback remains manual and component-scoped.

Both workflows connect to SSH alias `overtone-manager-ci`, whose pinned config uses `ProxyJump overtone-bastion-ci`; the manager is addressed only by `MANAGER_PRIVATE_HOST`. `DEPLOY_KNOWN_HOSTS` must contain entries for the exact public bastion `HostName` and exact private manager `HostName`. Obtain each host public key through a trusted provider console or existing authenticated administration channel, verify its `ssh-keygen -lf` fingerprint against an independently communicated value, then store the resulting known-host lines in the environment secret. CI never runs `ssh-keyscan`, accepts a host key interactively, or disables strict checking. See [docs/CLOUD-RELEASE.md](docs/CLOUD-RELEASE.md) for the full setup.

No workflow uses `latest`, performs a cloud deploy by default, deletes a volume, or rewrites the application repositories. Required GitHub environment/secrets are documented inside each workflow and in [docs/CLOUD-RELEASE.md](docs/CLOUD-RELEASE.md).

## Before cloud release

Replace local PostgreSQL/MinIO endpoints and credentials, TLS certificate, domain, admin CIDRs, inference worker address/tunnel key, registry references, node hostnames, Kuma push URL and notification destinations. The full checklist is [docs/CLOUD-RELEASE.md](docs/CLOUD-RELEASE.md).
