#!/bin/bash
# Dynamic Ansible inventory script that reads from Terraform output
# This makes the deployment fully automated

set -euo pipefail

TERRAFORM_DIR="../../terraform/environments/k8s-cluster"

# Change to script directory
cd "$(dirname "$0")"

# Check if --list or --host is passed (Ansible inventory script API)
if [ "$1" == "--list" ]; then
    # Output the full inventory from Terraform
    cd "$TERRAFORM_DIR" || { echo "Error: Terraform directory not found"; exit 1; }
    if ! terraform output -json ansible_inventory 2>/dev/null; then
        echo '{"_meta": {"hostvars": {}}}'
        exit 0
    fi
elif [ "$1" == "--host" ]; then
    # Ansible expects empty dict for --host <hostname>
    echo '{}'
else
    echo "Usage: $0 --list|--host <hostname>"
    exit 1
fi
