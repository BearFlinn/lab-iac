# Deployment Workflow: Packer + Terraform

This guide shows the complete workflow for building a Debian image with Packer and deploying VMs with Terraform.

## Workflow Overview

```
┌─────────────────────┐
│  Build with Packer  │
│  (QCOW2 output)     │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Import to Proxmox   │
│ (as VM template)    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│Deploy with Terraform│
│ (Clone VMs)         │
└─────────────────────┘
```

## Complete Workflow

### Step 1: Build Debian Image with Packer

```bash
cd packer

# Initialize Packer plugins
packer init debian-base.pkr.hcl

# Validate configuration
packer validate debian-base.pkr.hcl

# Build the image
packer build debian-base.pkr.hcl
```

Output: `packer/output-debian-base/` contains the QCOW2 image

### Step 2: Import Image to Proxmox

See [PROXMOX_SETUP.md](terraform/PROXMOX_SETUP.md) for detailed import instructions.

Quick summary:
```bash
# Copy image to Proxmox host
scp packer/output-debian-base/debian-base root@proxmox:/tmp/

# On Proxmox, create VM template from the image
# (Instructions vary by storage backend and import method)
```

### Step 3: Deploy VMs with Terraform

```bash
cd terraform/environments/dev

# Copy example vars file
cp dev.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
# - proxmox_url
# - proxmox_api_token
# - node names
# - storage IDs
# - network bridges

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var-file=terraform.tfvars

# Deploy
terraform apply -var-file=terraform.tfvars

# Verify deployment
terraform output
```

## Configuration Files

### Packer (`packer/`)
- `debian-base.pkr.hcl` - Main Packer template
- `vars/debian-base.pkrvars.hcl` - Packer variables
- `http/preseed.cfg` - Debian automated installation config

### Terraform (`terraform/`)
- `providers.tf` - Provider configuration
- `variables.tf` - Global variables
- `modules/compute/` - VM creation module
- `environments/dev/` - Development environment configuration
- `PROXMOX_SETUP.md` - Detailed setup guide

## Key Variables

### Packer
- `debian_version` - Debian version to build (default: 13.2.0)
- `debian_codename` - Debian codename (default: trixie)
- `disk_size` - VM disk size (default: 20G)
- `memory` - VM memory (default: 2048 MB)
- `cpus` - VM CPU cores (default: 2)

### Terraform
- `proxmox_url` - Proxmox API endpoint (required)
- `proxmox_api_token` - API token for authentication (required)
- `cloudinit_storage` - Storage for cloud-init CDROMs (required)
- `vms` - Map of VMs to create (required)

## Common Tasks

### Create a New VM Instance

Edit `terraform/environments/dev/terraform.tfvars`:

```hcl
vms = {
  web1 = {
    name    = "web1"
    node    = "proxmox1"
    vmid    = 100
    cores   = 2
    sockets = 1
    memory  = 2048
    networks = [{bridge = "vmbr0"}]
    disks = [{
      slot    = 0
      size    = "30G"
      storage = "local-lvm"
    }]
  }
  # Add more VMs here...
}
```

Then apply:
```bash
terraform apply -var-file=terraform.tfvars
```

### Update VM Configuration

Edit the VM definition in `terraform.tfvars` and apply:

```bash
terraform apply -var-file=terraform.tfvars
```

### Destroy VMs

```bash
# List resources to destroy
terraform plan -destroy -var-file=terraform.tfvars

# Destroy
terraform destroy -var-file=terraform.tfvars
```

### Export State

```bash
# List VMs created by Terraform
terraform output vms

# Get specific VM details
terraform state show 'module.compute.proxmox_vm_qemu.debian_vm["web1"]'
```

## Troubleshooting

### Packer Build Fails
```bash
# Validate syntax
packer validate debian-base.pkr.hcl

# Check ISO availability
curl -I https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.2.0-amd64-netinst.iso

# Enable debug logging
PACKER_LOG=1 packer build debian-base.pkr.hcl
```

### Terraform Apply Fails
```bash
# Validate Terraform configuration
terraform validate

# Check provider credentials
export TF_LOG=DEBUG terraform plan

# Verify Proxmox API access
curl -k -H "Authorization: PVEAPIToken=..." https://proxmox:8006/api2/json/nodes
```

### VMs Not Accessible via SSH
```bash
# Check VM status in Proxmox
qm status <vmid>

# Check VM IP address
qm monitor <vmid>
sudo ip route

# Verify SSH key permissions
chmod 600 ~/.ssh/id_rsa
```

## Next Steps

1. **Ansible Integration**: Add post-deployment configuration
2. **Networking Module**: Create advanced network configurations
3. **Storage Module**: Add persistent storage configurations
4. **Monitoring**: Integrate with monitoring/alerting systems
5. **CI/CD**: Automate builds and deployments with GitHub Actions/GitLab CI

## References

- [Packer Documentation](https://www.packer.io/docs)
- [Terraform Documentation](https://www.terraform.io/docs)
- [BPG Proxmox Provider](https://registry.terraform.io/providers/bpg/proxmox/latest)
- [Debian Preseed Guide](https://www.debian.org/releases/stable/amd64/preseed)
