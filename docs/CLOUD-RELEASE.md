# Cloud release checklist

1. Provision one manager and two workers with stable private networking and the Swarm ports listed in `VM-LAB.md`. Give every node outbound HTTPS access to the authenticated remote registry; never enable an insecure registry.
2. Put a load balancer/firewall in front of 80/443. Keep Docker, SSH, Kuma and external data-service ports private.
3. Replace the local self-signed TLS secrets with a real certificate, or terminate TLS at the cloud load balancer and retain trusted TLS on the internal hop.
4. Set `DATABASE_URL`/`WORKER_DATABASE_URL` to managed PostgreSQL. Use direct or session-pool mode; transaction pooling breaks the backend's advisory-lock semantics. Require TLS in the URL.
5. Set `S3_ENDPOINT`, region, bucket and credentials for cloud S3. Grant only the bucket/object operations required by Overtone and medical-scribe; enable encryption, retention and backups.
6. Change every versioned Docker secret name when rotating credentials. Deploy creates missing names but never overwrites or deletes an existing secret.
7. Replace `ADMIN_ALLOW_RULES` with office/VPN CIDRs. `allow all` is never a cloud setting.
8. Configure the worker's `INFERENCE_GRPC_ADDRESS` to the private worker address and reverse-tunnel port. On the SSH server set `GatewayPorts clientspecified`, restrict the tunnel account to forwarding, and firewall the port to Swarm nodes.
9. Configure Kuma monitors for public HTTPS, `/api/health`, and a Push monitor for `swarm-check`; attach notification channels and run `make alert-test`.
10. In the `overtone` code repository, create and protect the GitHub Environment named `production`; configure required reviewers and deployment branch/tag rules. A push to `main` automatically builds and pushes images, but production deploy runs only through `workflow_dispatch` when its `deploy` boolean is selected. Rollback is also manual and component-scoped.
11. Configure these values on the `overtone` repository:
    - variable `DOCKERHUB_USERNAME` — Docker Hub namespace used by both build and deploy;
    - secret `DOCKERHUB_TOKEN` — build/push credential with permission to push all four images;
    - secret `OVERTONE_INFRA_REPO_TOKEN` — read-only credential for checkout of the private `overtone-infra` repository.
12. Configure these values on the `overtone` repository's protected `production` Environment:
    - variable `BASTION_HOST`, or same-named secret — exact public DNS name or IP of the bastion;
    - variable `BASTION_USER` — `overtone_deploy`;
    - variable `MANAGER_PRIVATE_HOST`, or same-named secret — exact private DNS name or IP of the Swarm manager;
    - variable `DEPLOY_USER` — `overtone_deploy`;
    - secret `DEPLOY_SSH_KEY` — dedicated CI private key authorized for `overtone_deploy` on both hops;
    - secret `DEPLOY_KNOWN_HOSTS` — pinned host-key records for both exact host names/addresses;
    - secret `DOCKERHUB_TOKEN` — a distinct pull-only credential, not the repository build/push token.
13. Collect host keys out of band, never from the workflow. From a trusted provider console or an already authenticated administration path, read each server's SSH host public key and calculate its fingerprint with `ssh-keygen -lf`. Compare that fingerprint with a value obtained over an independent trusted channel. Only after it matches, create `known_hosts` records whose first fields are exactly the configured `BASTION_HOST` and `MANAGER_PRIVATE_HOST`, for example:

    ```text
    bastion.example.com ssh-ed25519 AAAA...
    10.0.1.10 ssh-ed25519 AAAA...
    ```

    Store both complete records in `DEPLOY_KNOWN_HOSTS`. Do not use runner-side `ssh-keyscan`, TOFU, or `StrictHostKeyChecking=no`.
14. Before the first deploy, place the completed production `.env` on the Swarm manager at `/opt/overtone-infra/.env`. Start from `.env.example`, replace local settings and secrets, and provision the file through a trusted administration channel. It must be owned by `overtone_deploy` with mode `0600`; keep a protected backup. The release workflow fails if this file is absent or has unsafe ownership or permissions. It never copies `.env` from GitHub: `rsync --delete` targets only `/opt/overtone-infra/` and excludes/protects the manager's root `.env`, alongside the existing `.git` and `local-certs` excludes. After syncing code, the manager updates only registry metadata and the four immutable image digest references in its `.env`.
15. Authorize the dedicated CI public key for the restricted `overtone_deploy` account on the bastion and manager. The workflows construct `overtone-bastion-ci` and `overtone-manager-ci` aliases with strict pinned-key checking; the manager alias reaches its private address with `ProxyJump overtone-bastion-ci`.
16. Keep registry tokens outside `.env`. The deploy sends the production pull-only token only over SSH standard input to `docker login --password-stdin`, uses a temporary `DOCKER_CONFIG` on the manager, and removes it on exit. Swarm forwards that short-lived login authorization to workers through the existing `docker stack deploy --with-registry-auth` operation.
17. Take volume/database backups, run the gated deploy, smoke and fault tests, then record each independently deployed image digest. Rollback remains `make rollback COMPONENT=...` (`backend`, `frontend`, `gateway`, or `all`) and performs its existing smoke test.

Never run `docker stack rm` as an upgrade mechanism and never add `-v` to the external Compose shutdown; both choices protect user data.
