#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Kubernetes Kubeconfig Setup${NC}"
echo "=================================="

# Prompt for SSH connection details
read -p "SSH Host (user@hostname or IP): " ssh_host
read -sp "SSH Password: " ssh_password
echo

# Optional: custom remote kubeconfig path
read -p "Remote kubeconfig path (default: ~/.kube/config): " remote_kube_path
remote_kube_path=${remote_kube_path:-"~/.kube/config"}

# Create local .kube directory if it doesn't exist
mkdir -p ~/.kube

echo -e "${YELLOW}Retrieving kubeconfig from $ssh_host:$remote_kube_path...${NC}"

# Use sshpass to automate password entry
if ! command -v sshpass &> /dev/null; then
    echo -e "${YELLOW}Installing sshpass...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y sshpass
    elif command -v yum &> /dev/null; then
        sudo yum install -y sshpass
    elif command -v brew &> /dev/null; then
        brew install sshpass
    else
        echo -e "${RED}Could not install sshpass. Please install it manually and try again.${NC}"
        exit 1
    fi
fi

# Copy the kubeconfig file
if sshpass -p "$ssh_password" scp -o StrictHostKeyChecking=no "$ssh_host:$remote_kube_path" ~/.kube/config 2>/dev/null; then
    chmod 600 ~/.kube/config
    echo -e "${GREEN}✓ Kubeconfig copied successfully to ~/.kube/config${NC}"
else
    echo -e "${RED}✗ Failed to copy kubeconfig. Check your credentials and path.${NC}"
    exit 1
fi

# Verify the connection
echo -e "${YELLOW}Verifying connection...${NC}"
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✓ Successfully connected to Kubernetes cluster${NC}"
else
    echo -e "${RED}✗ Could not connect to cluster. Check your kubeconfig.${NC}"
    exit 1
fi

# Install kubectl if not present
if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}Installing kubectl...${NC}"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    echo -e "${GREEN}✓ kubectl installed${NC}"
fi

# Setup K9s PATH if needed
if ! grep -q "envman/PATH.env" ~/.bashrc 2>/dev/null; then
    echo "source ~/.config/envman/PATH.env" >> ~/.bashrc
fi

echo
echo -e "${GREEN}Setup complete!${NC}"
echo "You can now run: ${YELLOW}k9s${NC}"
echo
echo "Quick commands:"
echo "  source ~/.config/envman/PATH.env  # Update PATH in current terminal"
echo "  k9s                                # Launch K9s dashboard"
