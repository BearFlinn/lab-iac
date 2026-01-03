#!/bin/bash
set -e

# Source environment variables
if [ -f ../packer.env ]; then
    source ../packer.env
fi

# Check required variables
if [ -z "$PKR_VAR_ssh_password" ]; then
    echo "Error: PKR_VAR_ssh_password not set. Source packer.env first."
    exit 1
fi

# Generate preseed.cfg from template
echo "Generating preseed.cfg from template..."
sed "s/__SSH_PASSWORD__/$PKR_VAR_ssh_password/g" http/preseed.cfg.template > http/preseed.cfg

# Run packer build
echo "Building Debian template..."
packer build -var-file=vars/debian-proxmox.pkrvars.hcl debian-proxmox.pkr.hcl

# Clean up generated preseed (optional - keeps it out of git)
# rm http/preseed.cfg
