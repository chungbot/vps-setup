#!/bin/bash
# Install Docker

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (use sudo)"
    exit 1
fi

USER_TO_ADD="${1:-claw}"

if command -v docker &> /dev/null; then
    echo "Docker already installed"
    exit 0
fi

echo "Installing Docker..."

# Remove old versions
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add repository
echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
if id "$USER_TO_ADD" &>/dev/null; then
    usermod -aG docker "$USER_TO_ADD"
    echo "Added $USER_TO_ADD to docker group"
fi

systemctl enable docker
systemctl start docker

echo "Docker installed successfully"
docker --version