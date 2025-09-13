#!/bin/bash

# Create kubeadmin user with same SSH access as anandy
set -euo pipefail

ORIGINAL_USER="anandy"
NEW_USER="kubeadmin"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

main() {
    log_info "Creating user: $NEW_USER"

    # Check if user already exists
    if id "$NEW_USER" &>/dev/null; then
        log_info "User $NEW_USER already exists"
    else
        # Create user
        sudo useradd -m -s /bin/bash -G sudo "$NEW_USER"
        log_success "Created user: $NEW_USER"
    fi

    # Set up SSH directory
    sudo mkdir -p "/home/$NEW_USER/.ssh"

    # Copy SSH keys from original user
    if [[ -d "/home/$ORIGINAL_USER/.ssh" ]]; then
        sudo cp -r "/home/$ORIGINAL_USER/.ssh/"* "/home/$NEW_USER/.ssh/" 2>/dev/null || true
        log_success "Copied SSH keys from $ORIGINAL_USER"
    fi

    # Set proper ownership and permissions
    sudo chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
    sudo chmod 700 "/home/$NEW_USER/.ssh"
    sudo chmod 600 "/home/$NEW_USER/.ssh/"* 2>/dev/null || true
    sudo chmod 644 "/home/$NEW_USER/.ssh/"*.pub 2>/dev/null || true

    # Add to sudoers
    echo "$NEW_USER ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$NEW_USER" > /dev/null
    sudo chmod 440 "/etc/sudoers.d/$NEW_USER"

    log_success "User $NEW_USER created successfully with sudo access"
}

main "$@"