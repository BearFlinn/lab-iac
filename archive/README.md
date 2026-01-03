# Archive

This directory contains archived infrastructure configurations that are no longer actively used but are preserved as portfolio material demonstrating skills progression.

## Why These Are Archived

The configurations in this archive were part of the homelab's evolution from a Proxmox-based virtualization playground to dedicated bare-metal Kubernetes infrastructure. The original laptop running Proxmox has been retired, and the infrastructure now runs on dedicated hardware (Dell OptiPlex nodes).

## Contents

### proxmox-playground/

Infrastructure as Code for provisioning a Kubernetes cluster on Proxmox VE:

- **Terraform**: Automated VM provisioning on Proxmox
- **Packer**: Custom Debian template images with cloud-init
- **Shell Scripts**: Cluster deployment and teardown automation
- **Documentation**: Setup guides and workflows

### migration-docs/

Documentation from the migration process to the current bare-metal infrastructure:

- Migration planning documents
- Step-by-step migration guides
- Integration documentation

## Skills Demonstrated

These archived materials showcase:

- **Infrastructure as Code**: Terraform modules, state management, provider configuration
- **Image Building**: Packer templates with cloud-init integration
- **Virtualization**: Proxmox VE API automation
- **Kubernetes**: Cluster bootstrapping and configuration
- **Automation**: Shell scripting for deployment workflows
- **Documentation**: Technical writing and architectural planning

## Note

This archive is preserved as a portfolio piece showing the progression from a virtualized playground environment to production-grade bare-metal infrastructure. The current active infrastructure configurations are in the root of this repository.
