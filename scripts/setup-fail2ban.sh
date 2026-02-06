#!/bin/bash
# Install and configure Fail2ban

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (use sudo)"
    exit 1
fi

SSH_PORT="${1:-22}"

echo "Installing Fail2ban..."
apt-get update
apt-get install -y fail2ban

echo "Configuring Fail2ban..."
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF

systemctl enable fail2ban
systemctl restart fail2ban

echo "Fail2ban installed and configured"
fail2ban-client status