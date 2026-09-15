# Three-VM Swarm lab

Use three disposable Linux VMs with unique hostnames and private addresses, for example:

| VM | Address | Role |
|---|---:|---|
| `manager-1` | `10.10.10.11` | manager, Kuma, swarm-check |
| `worker-1` | `10.10.10.12` | gateway, frontend, API, Redis |
| `worker-2` | `10.10.10.13` | gateway, frontend, worker, SSH tunnel endpoint |

Docker Engine must already be installed. The repository never installs host software. Open TCP 2377 and TCP/UDP 7946 between nodes, plus UDP 4789 for overlay traffic. Expose 80/443 only through the intended firewall/load balancer; keep Kuma 3001 private.

From the workstation:

```bash
export MANAGER_SSH=ubuntu@10.10.10.11 MANAGER_ADDR=10.10.10.11
export WORKER1_SSH=ubuntu@10.10.10.12 WORKER2_SSH=ubuntu@10.10.10.13
./scripts/lab/init-swarm.sh
```

Run PostgreSQL, MinIO and optionally the inference mock on a fourth reachable host or on the workstation with `EXTERNAL_BIND_ADDRESS` set to its private address. Set `DATABASE_URL`, `S3_ENDPOINT` and `INFERENCE_GRPC_ADDRESS` to that address—not to a Compose service name or loopback address.

Build/push images to a registry reachable by all VMs, set immutable image tags in `.env`, generate local TLS once, then:

```bash
./scripts/lab/sync-and-deploy.sh
make smoke
make fault-test
make alert-test
```

The node-drain test deliberately demonstrates the selected persistence tradeoff: API/Redis stop while `worker-1` is drained, then recover on the same node with the same local volumes. It does not delete volumes.

