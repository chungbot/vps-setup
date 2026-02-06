#!/bin/bash
# Harden SSH configuration

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (use sudo)"
    exit 1
fi

echo "Backing up SSH config..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d)

echo "Applying SSH hardening..."
cat >> /etc/ssh/sshd_config << 'EOF'

# Security hardening
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

systemctl restart sshd

echo "SSH hardened. Root login disabled, key auth only."
echo "WARNING: Ensure you have SSH key access before disconnecting!"