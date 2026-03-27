# Documentation Index

This directory contains documentation for the lab-iac infrastructure. Use this guide to find the right documentation for your needs.

## Quick Navigation

| Document | Purpose | Audience |
|----------|---------|----------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design and hardware specs | Understanding the infrastructure |
| [DEPLOYMENT.md](DEPLOYMENT.md) | How to deploy applications | Developers, operators |
| [RUNBOOKS.md](RUNBOOKS.md) | Operational procedures and fixes | Operators, troubleshooting |
| [../ansible/README.md](../ansible/README.md) | Ansible configuration details | Infrastructure setup |

## Suggested Reading Order

### For New Contributors
1. **[ARCHITECTURE.md](ARCHITECTURE.md)** - Understand the cluster layout and design decisions
2. **[DEPLOYMENT.md](DEPLOYMENT.md)** - Learn how applications are deployed
3. **[../ansible/README.md](../ansible/README.md)** - Understand the automation layer

### For Deploying Applications
1. **[DEPLOYMENT.md](DEPLOYMENT.md)** - GitOps patterns and Helm deployment
2. **[RUNBOOKS.md](RUNBOOKS.md)** - Common operations and troubleshooting

### For Infrastructure Operations
1. **[../ansible/README.md](../ansible/README.md)** - Playbook usage and inventory
2. **[RUNBOOKS.md](RUNBOOKS.md)** - Recovery procedures and fixes
3. **[ARCHITECTURE.md](ARCHITECTURE.md)** - Reference for node specs

## Active Documentation

These documents describe the current bare-metal Kubernetes infrastructure:

| File | Description |
|------|-------------|
| `ARCHITECTURE.md` | Cluster architecture, node specifications, network topology, and implementation phases |
| `DEPLOYMENT.md` | Application deployment patterns, GitOps workflow, Helm usage, secrets management |
| `RUNBOOKS.md` | Operational procedures, troubleshooting guides, recovery procedures |

## Reference Material

These documents contain historical or specialized information:

| File | Description |
|------|-------------|
| `PROXMOX_SETUP.md` | Archived - Proxmox API configuration (historical, VM-based setup) |
| `DEPLOYMENT_WORKFLOW.md` | Archived - Packer + Terraform workflow for VMs |
| `K8S_CLUSTER_SETUP.md` | Archived - Original VM-based K8s cluster setup |
| `kubernetes-migration-plan.md` | Historical - Migration from Docker Compose to K8s |
| `REMAINING_MIGRATION_STEPS.md` | Historical - Migration tracking document |
| `postgresql-service-integration.md` | Reference - PostgreSQL deployment patterns |
| `postgres-terraform-infisical-migration.md` | Reference - Secret management migration |
| `palworld-udp-forwarding.md` | Reference - Game server UDP forwarding setup |
| `DEBIAN_README.md` | Reference - Debian-specific configurations |

## Documentation Conventions

### File Naming
- `UPPERCASE.md` - Core documentation
- `lowercase-with-dashes.md` - Reference or specialized guides

### Status Indicators
Throughout the documentation, you may see:
- `[x]` - Completed task
- `[ ]` - Pending task
- `(archived)` - Historical, kept for reference
- `(planned)` - Future implementation

### Code Blocks
- Commands prefixed with `#` are comments or require root/sudo
- Commands without prefix run as normal user
- Multi-line commands use `\` for continuation

## Contributing to Documentation

When updating documentation:
1. Keep the focus on current bare-metal K8s architecture
2. Mark deprecated sections as `(archived)` rather than deleting
3. Include practical examples with actual commands
4. Update this index when adding new files
