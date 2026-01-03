# Proxmox Playground

This directory contains the Infrastructure as Code configurations used to provision a Kubernetes cluster on Proxmox VE running on an old laptop. This was the initial homelab setup before migrating to dedicated bare-metal hardware.

## What This Was Used For

A learning environment and playground for:

- Provisioning and managing VMs on Proxmox VE via Terraform
- Building custom OS images with Packer and cloud-init
- Bootstrapping Kubernetes clusters from scratch
- Experimenting with IaC workflows and automation

## Technologies Demonstrated

### Terraform

- **Proxmox Provider**: Automated VM lifecycle management via Proxmox API
- **Module Structure**: Reusable compute modules for VM provisioning
- **State Management**: Local state for single-user development environment
- **Variables & Environments**: Separation of dev/staging/prod configurations

### Packer

- **Proxmox Builder**: Creating VM templates directly on Proxmox
- **Cloud-Init Integration**: Automated first-boot configuration
- **Preseed/Autoinstall**: Unattended Debian installation
- **Template Optimization**: Minimal images for fast cloning

### Automation

- **deploy-k8s-cluster.sh**: One-command cluster provisioning
- **destroy-k8s-cluster.sh**: Clean teardown of resources
- **Cloud-Init Configs**: User-data for VM initialization

### Proxmox VE

- API-driven infrastructure management
- Template-based VM cloning
- Network and storage configuration

## Key Learnings

1. **IaC Workflow**: End-to-end automation from image building to cluster deployment
2. **Proxmox API**: Understanding hypervisor APIs and provider limitations
3. **Cloud-Init**: Mastering declarative VM configuration
4. **Kubernetes Bootstrap**: Manual cluster initialization process
5. **State Management**: Handling Terraform state in homelab environments

## Why Archived

The laptop running Proxmox has been retired and replaced with dedicated Dell OptiPlex nodes running bare-metal Kubernetes. This setup served its purpose as a learning environment and has been superseded by a more robust infrastructure.

## Directory Structure

```
proxmox-playground/
├── terraform/           # VM provisioning configurations
│   ├── environments/    # Environment-specific configs
│   └── modules/         # Reusable Terraform modules
├── packer/              # OS image building templates
├── deploy-k8s-cluster.sh
├── destroy-k8s-cluster.sh
├── proxy-vps-1_cloud-init.yml
└── docs/                # Setup and workflow documentation
```

## Note

This archive preserves the original work as a portfolio piece. The configurations may reference hardware, networks, or credentials that no longer exist.
