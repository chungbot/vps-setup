#!/bin/bash
# Install Homebrew (Linuxbrew)

set -euo pipefail

if command -v brew &> /dev/null; then
    echo "Homebrew already installed"
    exit 0
fi

echo "Installing Homebrew..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

brew install gcc

echo "Homebrew installed successfully"
brew --version