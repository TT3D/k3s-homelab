#!/usr/bin/env bash
set -Eeuo pipefail

log() {
    printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_root() {
    [[ $EUID -eq 0 ]] || die "Run this script with sudo."
}

usage() {
    cat <<'EOF'
Usage:
  sudo ./bootstrap-node.sh NODE_NAME ROLE

Examples:
  sudo ./bootstrap-node.sh cube02 worker
  sudo ./bootstrap-node.sh cube03 worker

Environment variables required for worker nodes:
  K3S_SERVER_URL=https://10.39.10.101:6443
  K3S_TOKEN=<cluster token>

Optional:
  K3S_VERSION=v1.36.2+k3s1
  NODE_IP=10.39.10.102
EOF
}

require_root

[[ $# -eq 2 ]] || {
    usage
    exit 1
}

NODE_NAME="$1"
NODE_ROLE="$2"

K3S_SERVER_URL="${K3S_SERVER_URL:-https://10.39.10.101:6443}"
K3S_VERSION="${K3S_VERSION:-}"
NODE_IP="${NODE_IP:-}"

case "$NODE_ROLE" in
    worker)
        [[ -n "${K3S_TOKEN:-}" ]] ||
            die "K3S_TOKEN is required for a worker node."
        ;;
    *)
        die "This version currently supports role: worker"
        ;;
esac

log "Configuring hostname as ${NODE_NAME}"
hostnamectl set-hostname "$NODE_NAME"

# Preserve local hostname resolution.
if grep -qE '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
    sed -i -E \
        "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1\t${NODE_NAME}/" \
        /etc/hosts
else
    printf '127.0.1.1\t%s\n' "$NODE_NAME" >> /etc/hosts
fi

log "Refreshing package metadata"
apt-get update

log "Installing base packages"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    git \
    jq \
    nfs-common \
    open-iscsi

log "Enabling required services"
systemctl enable --now iscsid

log "Checking cgroup support"
if ! mount | grep -q 'cgroup2 on /sys/fs/cgroup'; then
    echo "WARNING: unified cgroup v2 was not detected."
    echo "K3s requires functional cgroups."
fi

log "Removing a previous k3s agent installation, if present"
if [[ -x /usr/local/bin/k3s-agent-uninstall.sh ]]; then
    /usr/local/bin/k3s-agent-uninstall.sh
fi

INSTALL_ARGS=(
    agent
    "--node-name=${NODE_NAME}"
)

if [[ -n "$NODE_IP" ]]; then
    INSTALL_ARGS+=("--node-ip=${NODE_IP}")
fi

log "Installing k3s agent"

if [[ -n "$K3S_VERSION" ]]; then
    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_VERSION="$K3S_VERSION" \
        K3S_URL="$K3S_SERVER_URL" \
        K3S_TOKEN="$K3S_TOKEN" \
        sh -s - "${INSTALL_ARGS[@]}"
else
    curl -sfL https://get.k3s.io | \
        K3S_URL="$K3S_SERVER_URL" \
        K3S_TOKEN="$K3S_TOKEN" \
        sh -s - "${INSTALL_ARGS[@]}"
fi

log "Waiting for k3s-agent"
systemctl enable k3s-agent
systemctl restart k3s-agent

for attempt in {1..30}; do
    if systemctl is-active --quiet k3s-agent; then
        log "k3s-agent is running"
        break
    fi

    if [[ "$attempt" -eq 30 ]]; then
        journalctl -u k3s-agent --no-pager -n 100
        die "k3s-agent did not start."
    fi

    sleep 2
done

cat <<EOF

Bootstrap finished.

Node:       ${NODE_NAME}
Role:       ${NODE_ROLE}
Server:     ${K3S_SERVER_URL}

Verify from cube01 with:

    kubectl get nodes -o wide
    kubectl get pods -A -o wide

EOF
