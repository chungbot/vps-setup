#!/bin/bash
#
# VPS Setup Script for OpenClaw
# Hardens a fresh VPS and installs dependencies
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NEW_USER="${NEW_USER:-claw}"
SSH_PORT="${SSH_PORT:-22}"
OPENCLAW_PORT="${OPENCLAW_PORT:-7860}"
INSTALL_OPENCLAW="${INSTALL_OPENCLAW:-false}"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-}"

log() {
    echo -e "${GREEN}[SETUP]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install-openclaw)
                INSTALL_OPENCLAW=true
                shift
                ;;
            --config)
                OPENCLAW_CONFIG="$2"
                INSTALL_OPENCLAW=true
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --install-openclaw    Install OpenClaw after system setup"
                echo "  --config <file>       Use config file for OpenClaw setup"
                echo "  --help, -h            Show this help message"
                echo ""
                echo "Environment variables:"
                echo "  NEW_USER              Username to create (default: claw)"
                echo "  SSH_PORT              SSH port (default: 22)"
                echo "  OPENCLAW_PORT         OpenClaw port (default: 7860)"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

update_system() {
    log "Updating system packages..."
    apt-get update
    apt-get upgrade -y
    apt-get install -y \
        curl \
        wget \
        git \
        vim \
        htop \
        tmux \
        ufw \
        fail2ban \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        build-essential \
        python3 \
        python3-pip \
        python3-venv \
        nodejs \
        npm
}

create_user() {
    log "Creating user: $NEW_USER"
    
    if id "$NEW_USER" &>/dev/null; then
        warn "User $NEW_USER already exists"
        return
    fi
    
    # Create user with sudo access
    useradd -m -s /bin/bash "$NEW_USER"
    usermod -aG sudo "$NEW_USER"
    
    # Allow passwordless sudo for specific commands (optional, more secure)
    # echo "$NEW_USER ALL=(ALL) NOPASSWD: /bin/systemctl" > /etc/sudoers.d/$NEW_USER
    
    log "User $NEW_USER created. Set a password:"
    passwd "$NEW_USER"
}

setup_ssh() {
    log "Configuring SSH hardening..."
    
    # Backup original
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d)
    
    # Apply hardening
    cat >> /etc/ssh/sshd_config << 'EOF'

# Security hardening applied by OpenClaw setup
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
    
    systemctl restart sshd
    log "SSH configured. Root login disabled, key auth only."
    warn "Make sure you have SSH key access before disconnecting!"
}

setup_firewall() {
    log "Configuring UFW firewall..."
    
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "$SSH_PORT/tcp"
    ufw allow "$OPENCLAW_PORT/tcp"
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    ufw --force enable
    log "Firewall enabled. Allowed ports: $SSH_PORT (SSH), $OPENCLAW_PORT (OpenClaw), 80/443 (HTTP/HTTPS)"
}

setup_fail2ban() {
    log "Configuring Fail2ban..."
    
    # Create custom jail config
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
    systemctl start fail2ban
    log "Fail2ban configured and started"
}

install_homebrew() {
    log "Installing Homebrew..."
    
    if command -v brew &> /dev/null; then
        warn "Homebrew already installed"
        return
    fi
    
    # Install Homebrew (Linuxbrew)
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add to path for current session and new user
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /root/.bashrc
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    
    # Also add to new user
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/$NEW_USER/.bashrc
    chown $NEW_USER:$NEW_USER /home/$NEW_USER/.bashrc
    
    brew install gcc
    log "Homebrew installed"
}

install_docker() {
    log "Installing Docker..."
    
    if command -v docker &> /dev/null; then
        warn "Docker already installed"
        return
    fi
    
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
    usermod -aG docker "$NEW_USER"
    
    systemctl enable docker
    systemctl start docker
    
    log "Docker installed. User $NEW_USER added to docker group."
}

install_node() {
    log "Installing Node.js (via Nodesource)..."
    
    # Install Node.js 20.x
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    
    log "Node.js $(node --version) installed"
}

install_openclaw_deps() {
    log "Installing OpenClaw dependencies..."
    
    # Install bun (for some OpenClaw components)
    curl -fsSL https://bun.sh/install | bash
    mv /root/.bun /home/$NEW_USER/.bun
    chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.bun
    echo 'export PATH="$HOME/.bun/bin:$PATH"' >> /home/$NEW_USER/.bashrc
    
    # Install common global packages
    npm install -g pm2
    
    log "OpenClaw dependencies installed"
}

install_openclaw() {
    log "Installing OpenClaw..."
    
    # Install OpenClaw globally
    npm install -g openclaw
    
    # Create config directory
    mkdir -p /home/$NEW_USER/.config/openclaw
    chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.config
    
    if [ -n "$OPENCLAW_CONFIG" ] && [ -f "$OPENCLAW_CONFIG" ]; then
        log "Using provided config: $OPENCLAW_CONFIG"
        cp "$OPENCLAW_CONFIG" /home/$NEW_USER/.config/openclaw/config.json
        chown $NEW_USER:$NEW_USER /home/$NEW_USER/.config/openclaw/config.json
        
        # Run setup with config
        su - $NEW_USER -c "openclaw setup --config /home/$NEW_USER/.config/openclaw/config.json" || {
            warn "OpenClaw setup with config failed, trying interactive..."
            su - $NEW_USER -c "openclaw setup"
        }
    else
        log "No config provided, running interactive setup..."
        log "To automate, create openclaw-config.json and run with --config"
        su - $NEW_USER -c "openclaw setup"
    fi
    
    # Setup systemd service for OpenClaw gateway
    cat > /etc/systemd/system/openclaw-gateway.service << EOF
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
User=$NEW_USER
WorkingDirectory=/home/$NEW_USER
Environment=PATH=/home/$NEW_USER/.bun/bin:/usr/local/bin:/usr/bin:/bin
Environment=OPENCLAW_SERVICE_VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
ExecStart=/usr/bin/openclaw gateway start --foreground
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable openclaw-gateway
    
    log "OpenClaw installed and service created"
    log "Start with: sudo systemctl start openclaw-gateway"
}

setup_auto_updates() {
    log "Configuring automatic security updates..."
    
    apt-get install -y unattended-upgrades
    
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
    
    systemctl enable unattended-upgrades
    systemctl start unattended-upgrades
    
    log "Automatic security updates enabled"
}

print_summary() {
    echo ""
    echo "=========================================="
    echo -e "${GREEN}VPS Setup Complete!${NC}"
    echo "=========================================="
    echo ""
    echo "User created: $NEW_USER"
    echo "SSH port: $SSH_PORT"
    echo "OpenClaw port: $OPENCLAW_PORT"
    echo ""
    
    if [ "$INSTALL_OPENCLAW" = true ]; then
        echo -e "${GREEN}OpenClaw installed!${NC}"
        echo ""
        echo "Quick commands:"
        echo "  Start gateway:  sudo systemctl start openclaw-gateway"
        echo "  Check status:   sudo systemctl status openclaw-gateway"
        echo "  View logs:      sudo journalctl -u openclaw-gateway -f"
        echo ""
    else
        echo "Next steps:"
        echo "  1. Copy your SSH key to the new user:"
        echo "     ssh-copy-id $NEW_USER@<server-ip>"
        echo ""
        echo "  2. Switch to the new user:"
        echo "     su - $NEW_USER"
        echo ""
        echo "  3. Install OpenClaw:"
        echo "     npm install -g openclaw"
        echo "     openclaw setup"
        echo ""
    fi
    
    echo "  Review firewall status:"
    echo "     ufw status"
    echo ""
    echo "  Review fail2ban status:"
    echo "     fail2ban-client status"
    echo ""
    echo -e "${YELLOW}IMPORTANT:${NC} Test SSH access as $NEW_USER before closing this session!"
    echo ""
}

# Main
main() {
    parse_args "$@"
    
    log "Starting VPS setup for OpenClaw..."
    
    check_root
    update_system
    create_user
    setup_ssh
    setup_firewall
    setup_fail2ban
    install_homebrew
    install_docker
    install_node
    install_openclaw_deps
    setup_auto_updates
    
    if [ "$INSTALL_OPENCLAW" = true ]; then
        install_openclaw
    fi
    
    print_summary
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi