#!/bin/bash
# Setup UFW firewall

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (use sudo)"
    exit 1
fi

SSH_PORT="${1:-22}"
OPENCLAW_PORT="${2:-7860}"

echo "Configuring UFW firewall..."

ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp"
ufw allow "$OPENCLAW_PORT/tcp"
ufw allow 80/tcp
ufw allow 443/tcp

ufw --force enable

echo "Firewall enabled. Allowed ports:"
ufw status