# Cloud release checklist

1. Provision one manager and two workers with stable private networking and the Swarm ports listed in `VM-LAB.md`.
2. Put a load balancer/firewall in front of 80/443. Keep Docker, SSH, Kuma and external data-service ports private.
3. Replace the local self-signed TLS secrets with a real certificate, or terminate TLS at the cloud load balancer and retain trusted TLS on the internal hop.
4. Set `DATABASE_URL`/`WORKER_DATABASE_URL` to managed PostgreSQL. Use direct or session-pool mode; transaction pooling breaks the backend's advisory-lock semantics. Require TLS in the URL.
5. Set `S3_ENDPOINT`, region, bucket and credentials for cloud S3. Grant only the bucket/object operations required by Overtone and medical-scribe; enable encryption, retention and backups.
6. Change every versioned Docker secret name when rotating credentials. Deploy creates missing names but never overwrites or deletes an existing secret.
7. Replace `ADMIN_ALLOW_RULES` with office/VPN CIDRs. `allow all` is never a cloud setting.
8. Configure the worker's `INFERENCE_GRPC_ADDRESS` to the private worker address and reverse-tunnel port. On the SSH server set `GatewayPorts clientspecified`, restrict the tunnel account to forwarding, and firewall the port to Swarm nodes.
9. Configure Kuma monitors for public HTTPS, `/api/health`, and a Push monitor for `swarm-check`; attach notification channels and run `make alert-test`.
10. Take volume/database backups, run deploy, smoke and fault tests, then record the deployed Git SHA tags. Rollback is `make rollback COMPONENT=...`.

Never run `docker stack rm` as an upgrade mechanism and never add `-v` to the external Compose shutdown; both choices protect user data.
