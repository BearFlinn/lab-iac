# Terraform Proxmox Deployment Guide

This guide explains how to deploy the Debian base image built with Packer to your Proxmox server using Terraform.

## Prerequisites

1. **Proxmox Setup**:
   - Proxmox VE 7.0+ installed and accessible
   - API token created with appropriate permissions
   - SSH access to Proxmox host
   - Storage configured (e.g., local-lvm, local)

2. **Local Setup**:
   - Terraform 1.0+
   - SSH key pair for VM access
   - Packer-built Debian image already imported as a template in Proxmox

## Step 1: Create Proxmox API Token

On your Proxmox host:

```bash
# Create a new user (optional)
pveum user add terraform@pve

# Create an API token
pveum acl modify / -user terraform@pve -role Administrator

pveum user token add terraform@pve terraform-token
```

Store the token in format: `user@realm!tokenid=tokensecret`

## Step 2: Import Packer Image as Template

First, convert the Packer QCOW2 output and import it to Proxmox:

```bash
# Copy the image from Packer output to Proxmox host
scp packer/output-debian-base/debian-base root@proxmox.example.com:/tmp/

# On Proxmox host, convert and import
qm create 900 \
  --name debian-base \
  --memory 2048 \
  --cores 2 \
  --sockets 1 \
  --net0 virtio,bridge=vmbr0 \
  --scsi0 local-lvm:0,discard=on \
  --ostype l26 \
  --template

# Or use the qcow2 image directly
qmimg import /tmp/debian-base local-lvm raw --format qcow2
```

> **Note**: The exact import process depends on your Proxmox storage backend. Consult Proxmox documentation for your specific setup.

## Step 3: Configure Terraform Variables

Create `terraform/environments/dev/terraform.tfvars`:

```hcl
# Proxmox API endpoint
proxmox_url = "https://proxmox.example.com:8006"

# API token (keep this secure!)
proxmox_api_token = "terraform@pve!terraform-token=your-token-secret"

# Allow self-signed certificates (development only)
proxmox_insecure = true

# SSH configuration
proxmox_ssh_user     = "root"
ssh_private_key_path = "~/.ssh/id_rsa"

# Proxmox storage and template
cloudinit_storage = "local-lvm"

# Define VMs
vms = {
  web1 = {
    name    = "web1"
    node    = "proxmox1"
    vmid    = 100
    cores   = 2
    sockets = 1
    memory  = 2048
    networks = [
      {
        bridge = "vmbr0"
      }
    ]
    disks = [
      {
        slot    = 0
        size    = "30G"
        storage = "local-lvm"
      }
    ]
  }
}
```

## Step 4: Initialize Terraform

```bash
cd terraform/environments/dev
terraform init
```

## Step 5: Plan and Apply

```bash
# Review changes
terraform plan -var-file=terraform.tfvars

# Apply configuration
terraform apply -var-file=terraform.tfvars
```

## Security Best Practices

1. **API Token**: Store sensitive values in `.tfvars` or use environment variables:
   ```bash
   export TF_VAR_proxmox_api_token="..."
   ```

2. **SSH Key**: Ensure your SSH private key has restricted permissions:
   ```bash
   chmod 600 ~/.ssh/id_rsa
   ```

3. **State File**: Protect your Terraform state (contains sensitive data):
   ```bash
   terraform state list  # Never commit .tfstate files
   ```

4. **Production**: Use remote state backend (Terraform Cloud, S3, etc.) and enable state locking.

## Troubleshooting

### Connection Issues
```bash
# Test Proxmox API connectivity
curl -k -H "Authorization: PVEAPIToken=token_id=token_secret" \
  https://proxmox.example.com:8006/api2/json/version
```

### SSH Access
```bash
# Test SSH access to VMs
ssh -i ~/.ssh/id_rsa debian@<vm-ip>
```

### Template Not Found
```bash
# List available templates in Proxmox
qm list --full
```

## Module Structure

```
terraform/
├── providers.tf          # Provider configuration
├── variables.tf          # Global variables
├── modules/
│   └── compute/          # VM creation module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── environments/
    ├── dev/
    ├── staging/
    └── prod/
```

## Next Steps

1. Create templates for staging and production environments
2. Add networking module for advanced network configurations
3. Set up remote state backend for team collaboration
4. Add Ansible provisioning for post-deployment configuration

## Resources

- [BPG Proxmox Provider Documentation](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Proxmox API Documentation](https://pve.proxmox.com/pve-docs/api-viewer/)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices)
