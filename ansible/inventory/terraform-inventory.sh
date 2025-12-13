#!/bin/bash
# Dynamic Ansible inventory script that reads from Terraform output
# This makes the deployment fully automated

set -e

TERRAFORM_DIR="../../terraform/environments/k8s-cluster"

# Change to script directory
cd "$(dirname "$0")"

# Check if --list or --host is passed (Ansible inventory script API)
if [ "$1" == "--list" ]; then
    # Output the full inventory from Terraform
    cd "$TERRAFORM_DIR"
    terraform output -json ansible_inventory | jq -r '.'
elif [ "$1" == "--host" ]; then
    # Ansible expects empty dict for --host <hostname>
    echo '{}'
else
    echo "Usage: $0 --list|--host <hostname>"
    exit 1
fi
