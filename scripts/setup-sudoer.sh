#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

# Function to install sudo
install_sudo() {
    local distro=$1
    echo -e "${YELLOW}Installing sudo...${NC}"

    case $distro in
        ubuntu|debian)
            apt-get update
            apt-get install -y sudo
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v dnf &> /dev/null; then
                dnf install -y sudo
            else
                yum install -y sudo
            fi
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm sudo
            ;;
        opensuse*|sles)
            zypper install -y sudo
            ;;
        alpine)
            apk add sudo
            ;;
        *)
            echo -e "${RED}Unknown distribution. Please install sudo manually.${NC}"
            exit 1
            ;;
    esac

    echo -e "${GREEN}sudo installed successfully${NC}"
}

# Function to add user to sudoers using file method
add_to_sudoers() {
    local username=$1
    local require_password=$2

    # Verify user exists
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}Error: User '$username' does not exist${NC}"
        exit 1
    fi

    # Create sudoers file
    local sudoers_file="/etc/sudoers.d/$username"

    echo -e "${YELLOW}Creating sudoers file at $sudoers_file${NC}"

    if [[ $require_password =~ ^[Nn]$ ]]; then
        echo "$username ALL=(ALL) NOPASSWD: ALL" > "$sudoers_file"
        echo -e "${GREEN}Configured passwordless sudo for $username${NC}"
    else
        echo "$username ALL=(ALL) ALL" > "$sudoers_file"
        echo -e "${GREEN}Configured sudo with password for $username${NC}"
    fi

    # Set correct permissions
    chmod 0440 "$sudoers_file"

    # Validate sudoers file if visudo is available
    if command -v visudo &>/dev/null; then
        if visudo -c -f "$sudoers_file" &>/dev/null; then
            echo -e "${GREEN}Sudoers file validated successfully${NC}"
        else
            echo -e "${RED}Error: Invalid sudoers file syntax${NC}"
            rm -f "$sudoers_file"
            exit 1
        fi
    else
        echo -e "${YELLOW}Warning: visudo not available, skipping validation${NC}"
    fi
}

# Main script execution when running on remote as root
main_as_root() {
    echo -e "${GREEN}=== Sudo Setup Script ===${NC}"
    echo "This script will install sudo (if needed) and configure sudoer access"
    echo ""

    # Detect distribution
    DISTRO=$(detect_distro)
    echo -e "${GREEN}Detected distribution: $DISTRO${NC}"
    echo ""

    # Check if sudo is installed
    if ! command -v sudo &> /dev/null; then
        echo -e "${YELLOW}sudo is not installed${NC}"
        echo "Installing sudo..."
        install_sudo "$DISTRO"
    else
        echo -e "${GREEN}sudo is already installed${NC}"
    fi

    echo ""

    # Get username from environment
    if [ -n "$TARGET_USER" ]; then
        USERNAME="$TARGET_USER"
        echo -e "${GREEN}Granting sudo access to: $USERNAME${NC}"
    else
        echo -e "${RED}Error: TARGET_USER not set${NC}"
        exit 1
    fi

    echo ""

    # Get password requirement from environment
    REQUIRE_PASSWORD="${REQUIRE_PASSWORD:-y}"

    # Add user to sudoers using file method
    add_to_sudoers "$USERNAME" "$REQUIRE_PASSWORD"

    echo ""
    echo -e "${GREEN}=== Setup Complete ===${NC}"
    echo -e "${GREEN}User '$USERNAME' now has sudo access${NC}"
}

# Main entry point
if [ -n "$REMOTE_MODE" ]; then
    # Running on remote machine - check if root
    if [ "$EUID" -eq 0 ]; then
        # Already root, proceed
        main_as_root
    else
        # Not root, need to escalate with su
        echo -e "${YELLOW}Escalating to root...${NC}"
        CURRENT_USER=$(whoami)
        exec su -c "REMOTE_MODE=1 TARGET_USER='$CURRENT_USER' REQUIRE_PASSWORD='$REQUIRE_PASSWORD' '$0'" root
    fi
else
    # Running locally - handle SSH connection
    echo -e "${GREEN}=== Remote Sudo Setup Script ===${NC}"
    echo ""

    # Get remote connection details
    read -p "Enter remote host (hostname or IP): " REMOTE_HOST
    if [ -z "$REMOTE_HOST" ]; then
        echo -e "${RED}Error: Remote host is required${NC}"
        exit 1
    fi

    read -p "Enter SSH username: " SSH_USER
    if [ -z "$SSH_USER" ]; then
        echo -e "${RED}Error: SSH username is required${NC}"
        exit 1
    fi

    read -p "Enter SSH port (default: 22): " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}

    echo ""
    read -p "Require password for sudo? (y/n, default: y): " REQUIRE_PASSWORD
    REQUIRE_PASSWORD=${REQUIRE_PASSWORD:-y}

    echo ""
    echo -e "${YELLOW}Connecting to $SSH_USER@$REMOTE_HOST:$SSH_PORT...${NC}"
    echo -e "${YELLOW}You will be prompted for:${NC}"
    echo -e "${YELLOW}  1. SSH password for $SSH_USER${NC}"
    echo -e "${YELLOW}  2. Root password on the remote machine${NC}"
    echo ""

    # Copy script to remote and execute
    SCRIPT_PATH=$(readlink -f "$0")
    REMOTE_SCRIPT="/tmp/setup-sudoer-$$.sh"

    # Use scp to copy the script
    if ! scp -P "$SSH_PORT" "$SCRIPT_PATH" "$SSH_USER@$REMOTE_HOST:$REMOTE_SCRIPT"; then
        echo -e "${RED}Failed to copy script to remote host${NC}"
        exit 1
    fi

    # Execute the script on remote with REMOTE_MODE flag
    ssh -p "$SSH_PORT" -t "$SSH_USER@$REMOTE_HOST" "chmod +x '$REMOTE_SCRIPT' && REMOTE_MODE=1 REQUIRE_PASSWORD='$REQUIRE_PASSWORD' '$REMOTE_SCRIPT' && rm -f '$REMOTE_SCRIPT'"

    echo ""
    echo -e "${GREEN}=== Remote setup completed ===${NC}"
fi
