# Admin and Uptime Kuma access through bastion

The public HAProxy continues to forward only 80/443. The gateway returns 404
for `/admin` and `/api/admin` on those ports. A separate HTTPS listener on
each worker's private TCP 8443 serves the admin UI and API. Uptime Kuma stays
on the manager's private TCP 3001.

Before deployment:

1. Use `priemo.tech` for the public site and `admin.priemo.tech` for admin.
   The admin name needs no public A/AAAA record. Issue a trusted certificate
   whose SAN covers both names using the local Ansible manual DNS-01 procedure
   in `../overtone-ansible/docs/TLS-CERTIFICATE.md`. Stage it on the manager,
   then supply the files through the existing `TLS_CERT_FILE`/`TLS_KEY_FILE`
   settings. Rotate the versioned secret names when replacing an existing
   certificate.
2. Set `PUBLIC_SERVER_NAME=priemo.tech`,
   `ADMIN_SERVER_NAME=admin.priemo.tech` and
   `ADMIN_BASTION_CIDR=10.16.0.6/32` in the manager's `.env`. The CIDR is an
   additional Nginx source check, not a substitute for the host firewall.
3. Before publishing 8443/3001, apply the `overtone-ansible` firewall playbook
   to both workers and the manager. Its pre-DNAT guard permits worker 8443
   and manager 3001 on each host's private IP only from bastion `10.16.0.6`
   on the private interface. It drops other traffic to those private IPs and
   public-interface traffic to these ports, including IPv6, without affecting
   overlay service destinations. UFW also permits bastion privately.
   Docker-published ports can bypass ordinary UFW rules; keep public HAProxy
   80/443 unchanged.
4. Apply the matching local `overtone-ansible` SSH changes to bastion after
   reviewing the playbook. The assistant must not execute Ansible or connect
   to these servers; the operator runs it.

Before stack deployment, the operator reviews Ansible's changes from the
`overtone-ansible` directory. Keep an existing SSH session and provider console
available before the real runs:

```bash
ansible-playbook -i inventories/production/hosts.yml playbooks/30-ssh-policy.yml \
  --limit bastion -e access_policy_confirmed=true --check --diff
ansible-playbook -i inventories/production/hosts.yml playbooks/20-firewall.yml \
  --limit manager-1,worker-1,worker-2 -e access_policy_confirmed=true --check --diff
```

After reviewing the output, repeat those commands without `--check --diff`.
The firewall role adds UFW allowances and a persistent raw/PREROUTING drop for
the public private-service ports. Verify its iptables and ip6tables checks
succeed on every Swarm node. If old wide allow rules already exist, inspect
and remove them explicitly. Then run the read-only `playbooks/90-audit.yml`
yourself. No production commands are run by the assistant.

On the Mac, map the admin name to local loopback in `/etc/hosts`:

```text
127.0.0.1 admin.priemo.tech
```

Start the forwards using the current production inventory. Keep this process
open while using the sites:

```bash
ssh -N -T -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:8443:10.16.0.3:8443 \
  -L 127.0.0.1:13001:10.16.0.2:3001 \
  overtone-bastion
```

Open `https://admin.priemo.tech:8443/admin` and
`http://127.0.0.1:13001` (Kuma). The admin application uses secure,
same-origin cookies and relative `/api` requests, so use the HTTPS name in the
certificate, not `https://127.0.0.1:8443` or plain HTTP. The public site will
not show an admin navigation link; bookmark the private URL.

If worker `10.16.0.3` is unavailable, restart the tunnel with `10.16.0.4`
instead.

To verify, check from a network **outside** the private network that worker
public IP TCP 8443 and manager public IP TCP 3001 are unreachable, and that
`/admin` and `/api/admin` on public 80/443 return 404. Check the private URLs
through the SSH tunnel. Do not claim isolation until these checks pass.
