# Three-VM Swarm lab

Use three disposable Linux VMs with unique hostnames and private addresses, for example:

| VM | Address | Role |
|---|---:|---|
| `manager-1` | `10.10.10.11` | manager, Kuma, swarm-check |
| `worker-1` | `10.10.10.12` | gateway, frontend, API, Redis |
| `worker-2` | `10.10.10.13` | gateway, frontend, worker, SSH tunnel endpoint |

Docker Engine must already be installed. The repository never installs host software. Open TCP 2377 and TCP/UDP 7946 between nodes, plus UDP 4789 for overlay traffic. Expose 80/443 only through the intended firewall/load balancer; keep Kuma 3001 private. Every host needs outbound HTTPS access to the configured remote registry; do not run a local registry or configure Docker insecure registries.

From the workstation:

```bash
export MANAGER_SSH=ubuntu@10.10.10.11 MANAGER_ADDR=10.10.10.11
export WORKER1_SSH=ubuntu@10.10.10.12 WORKER2_SSH=ubuntu@10.10.10.13
./scripts/lab/init-swarm.sh
```

Run PostgreSQL, MinIO and optionally the inference mock on a fourth reachable host or on the workstation with `EXTERNAL_BIND_ADDRESS` set to its private address. Set `DATABASE_URL`, `S3_ENDPOINT` and `INFERENCE_GRPC_ADDRESS` to that address—not to a Compose service name or loopback address.

Set `REGISTRY_HOST` and `REGISTRY_USERNAME` in `.env`. `make build` calculates the four independent content versions, builds the images, and writes the ignored `swarm/images.yml` override with their tags. `make push` publishes those exact references. Registry tokens are shell-only secrets and must never be stored in `.env`:

```bash
make build
export REGISTRY_PUSH_TOKEN=...
make push
unset REGISTRY_PUSH_TOKEN

export REGISTRY_PULL_TOKEN=...
./scripts/lab/sync-and-deploy.sh
unset REGISTRY_PULL_TOKEN

BASE_URL=https://10.10.10.11 TLS_INSECURE=true make smoke
ssh -t "$MANAGER_SSH" 'cd /opt/overtone-infra && ./scripts/fault-test.sh'
ssh -t "$MANAGER_SSH" 'cd /opt/overtone-infra && ./scripts/uptime-alert-test.sh'
```

`REGISTRY_PUSH_TOKEN` needs permission to publish packages. `REGISTRY_PULL_TOKEN` only needs read/pull permission; for a disposable lab they may contain the same token. `sync-and-deploy.sh` logs the manager in through stdin, then `docker stack deploy --with-registry-auth` supplies pull authorization to workers. No token is copied into the repository or `.env`.

The node-drain test deliberately demonstrates the selected persistence tradeoff: API/Redis stop while `worker-1` is drained, then recover on the same node with the same local volumes. It does not delete volumes.
