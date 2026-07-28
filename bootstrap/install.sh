#!/usr/bin/env bash
set -Eeuo pipefail

log() {
    printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  sudo ./bootstrap/install.sh NODE_NAME

Examples:
  sudo ./bootstrap/install.sh cube02
  sudo ./bootstrap/install.sh cube03

This script:
  - Loads bootstrap/config.env
  - Validates the required settings
  - Runs bootstrap-node.sh as a worker
EOF
}

[[ $EUID -eq 0 ]] || die "Run this script with sudo."

[[ $# -eq 1 ]] || {
    usage
    exit 1
}

NODE_NAME="$1"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
BOOTSTRAP_SCRIPT="${SCRIPT_DIR}/bootstrap-node.sh"

[[ -f "$CONFIG_FILE" ]] ||
    die "Missing ${CONFIG_FILE}. Copy config.example.env to config.env and add your token."

[[ -x "$BOOTSTRAP_SCRIPT" ]] ||
    die "${BOOTSTRAP_SCRIPT} is missing or not executable."

log "Loading configuration from ${CONFIG_FILE}"

set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

[[ -n "${K3S_SERVER_URL:-}" ]] ||
    die "K3S_SERVER_URL is missing from config.env."

[[ -n "${K3S_TOKEN:-}" ]] ||
    die "K3S_TOKEN is missing from config.env."

case "$NODE_NAME" in
    cube02)
        NODE_IP="${NODE_IP:-10.39.10.102}"
        ;;
    cube03)
        NODE_IP="${NODE_IP:-10.39.10.103}"
        ;;
    cube01)
        die "cube01 is the control-plane. This installer currently supports workers only."
        ;;
    *)
        die "Unknown node '${NODE_NAME}'. Supported workers: cube02, cube03."
        ;;
esac

export K3S_SERVER_URL
export K3S_TOKEN
export K3S_VERSION="${K3S_VERSION:-v1.36.2+k3s1}"
export NODE_IP

cat <<EOF

Worker bootstrap configuration

Node:        ${NODE_NAME}
Role:        worker
Node IP:     ${NODE_IP}
K3s server:  ${K3S_SERVER_URL}
K3s version: ${K3S_VERSION}

EOF

read -r -p "Continue? [y/N] " CONFIRM

case "$CONFIRM" in
    y|Y|yes|YES)
        ;;
    *)
        die "Cancelled."
        ;;
esac

log "Starting worker bootstrap"

exec "$BOOTSTRAP_SCRIPT" "$NODE_NAME" worker
