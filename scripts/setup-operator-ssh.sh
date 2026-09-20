#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/setup-operator-ssh.sh [--skip-keygen]

Creates an isolated Overtone SSH layout under ~/.ssh/overtone-infra,
adds its config directory to ~/.ssh/config, and optionally generates an
Ed25519 operator key.

Environment overrides (mainly useful for testing):
  OVERTONE_SSH_DIR   default: ~/.ssh/overtone-infra
  SSH_CONFIG_FILE    default: ~/.ssh/config
EOF
}

generate_key=true
case "${1:-}" in
  "") ;;
  --skip-keygen) generate_key=false ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
(( $# <= 1 )) || { usage >&2; exit 2; }

command -v ssh >/dev/null 2>&1 || { echo "required command not found: ssh" >&2; exit 1; }
if [[ "$generate_key" == true ]]; then
  command -v ssh-keygen >/dev/null 2>&1 || {
    echo "required command not found: ssh-keygen" >&2
    exit 1
  }
fi

user_home="${HOME:?HOME is not set}"
ssh_root="${OVERTONE_SSH_DIR:-$user_home/.ssh/overtone-infra}"
main_config="${SSH_CONFIG_FILE:-$user_home/.ssh/config}"
config_dir="$ssh_root/config"
keys_dir="$ssh_root/keys"
known_hosts_dir="$ssh_root/known_hosts"
hosts_config="$config_dir/hosts.conf"
private_key="$keys_dir/overtone-production"
known_hosts_file="$known_hosts_dir/known_hosts"
include_glob="$config_dir/*.conf"
include_line="Include $include_glob"

mkdir -p "$(dirname "$main_config")" "$config_dir" "$keys_dir" "$known_hosts_dir"
chmod 700 "$(dirname "$main_config")" "$ssh_root" "$config_dir" "$keys_dir" "$known_hosts_dir"

if [[ ! -e "$known_hosts_file" ]]; then
  : > "$known_hosts_file"
fi
chmod 600 "$known_hosts_file"

if [[ ! -e "$hosts_config" ]]; then
  cat > "$hosts_config" <<EOF
# Replace every CHANGE_ME value before connecting.
# Keep this file and the private key outside version control.

Host overtone-bastion
  HostName CHANGE_ME_BASTION_PUBLIC_IP
  User deploy
  IdentityFile $private_key
  IdentitiesOnly yes
  UserKnownHostsFile $known_hosts_file

Host overtone-manager
  HostName CHANGE_ME_MANAGER_PRIVATE_IP
  User deploy
  IdentityFile $private_key
  IdentitiesOnly yes
  UserKnownHostsFile $known_hosts_file
  ProxyJump overtone-bastion

Host overtone-worker-1
  HostName CHANGE_ME_WORKER1_PRIVATE_IP
  User deploy
  IdentityFile $private_key
  IdentitiesOnly yes
  UserKnownHostsFile $known_hosts_file
  ProxyJump overtone-bastion

Host overtone-worker-2
  HostName CHANGE_ME_WORKER2_PRIVATE_IP
  User deploy
  IdentityFile $private_key
  IdentitiesOnly yes
  UserKnownHostsFile $known_hosts_file
  ProxyJump overtone-bastion

Host overtone-haproxy
  HostName CHANGE_ME_HAPROXY_PRIVATE_IP
  User deploy
  IdentityFile $private_key
  IdentitiesOnly yes
  UserKnownHostsFile $known_hosts_file
  ProxyJump overtone-bastion
EOF
  chmod 600 "$hosts_config"
  echo "created SSH host template: $hosts_config"
else
  echo "kept existing SSH host template: $hosts_config"
fi

if [[ ! -e "$main_config" ]]; then
  : > "$main_config"
  chmod 600 "$main_config"
fi

if ! grep -Fqx "$include_line" "$main_config"; then
  candidate="$(mktemp "${TMPDIR:-/tmp}/overtone-ssh-config.XXXXXX")"
  trap 'rm -f "${candidate:-}"' EXIT
  {
    printf '%s\n\n' "$include_line"
    cat "$main_config"
  } > "$candidate"
  chmod 600 "$candidate"
  ssh -G -F "$candidate" overtone-bastion >/dev/null
  cp "$candidate" "$main_config"
  chmod 600 "$main_config"
  rm -f "$candidate"
  trap - EXIT
  echo "added Overtone Include to: $main_config"
else
  echo "kept existing Overtone Include in: $main_config"
fi

if [[ "$generate_key" == true ]]; then
  if [[ -e "$private_key" || -e "$private_key.pub" ]]; then
    echo "kept existing SSH key material in: $keys_dir"
  else
    echo "Generating the Overtone operator key. Use a strong passphrase."
    ssh-keygen -t ed25519 -a 100 -C overtone-production -f "$private_key"
    chmod 600 "$private_key"
    chmod 644 "$private_key.pub"
  fi
else
  echo "skipped SSH key generation"
fi

cat <<EOF

SSH layout is ready:
  config:     $hosts_config
  private key: $private_key
  public key:  $private_key.pub
  known hosts: $known_hosts_file

Next:
  1. Replace CHANGE_ME values in $hosts_config.
  2. Install $private_key.pub for the deploy user on every server.
  3. Test: ssh overtone-bastion, then ssh overtone-manager/workers/haproxy.
  4. Harden SSH and close public node access only after every test succeeds.
EOF
