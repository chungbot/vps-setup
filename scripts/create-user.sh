#!/bin/bash
# Create non-root user with sudo access

set -euo pipefail

NEW_USER="${1:-claw}"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (use sudo)"
    exit 1
fi

if id "$NEW_USER" &>/dev/null; then
    echo "User $NEW_USER already exists"
    exit 0
fi

echo "Creating user: $NEW_USER"
useradd -m -s /bin/bash "$NEW_USER"
usermod -aG sudo "$NEW_USER"

echo "Set password for $NEW_USER:"
passwd "$NEW_USER"

echo "User $NEW_USER created with sudo access"