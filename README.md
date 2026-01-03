# Infrastructure as Code Portfolio

A DevOps portfolio demonstrating infrastructure automation, Kubernetes orchestration, and GitOps practices through a production-ready bare-metal home lab environment.

## Current Architecture

This repository manages a **bare-metal Kubernetes cluster** built on repurposed hardware, showcasing real-world infrastructure automation skills applicable to cloud and on-premises environments.

```
Internet Traffic
      |
      v
+------------------+
|   Hetzner VPS    |  Caddy reverse proxy with auto TLS
|   (proxy-vps)    |  Wildcard certificates via Cloudflare DNS-01
+--------+---------+
         |
    NetBird VPN
         |
         v
+------------------+     +------------------+     +------------------+
| Dell Inspiron 15 |     |    MSI Laptop    |     |     Tower PC     |
| (Control Plane)  |     |     (Worker)     |     |     (Worker)     |
| i3-7100U, 8GB    |     | i7-6700HQ, 32GB  |     | i7-4790, 32GB    |
|                  |     | GTX 1060 GPU     |     | GTX 1060 GPU     |
+--------+---------+     +--------+---------+     +--------+---------+
         |                        |                        |
         +------------------------+------------------------+
                                  |
                     +------------+------------+
                     |   Dell Optiplex 9020   |
                     |       (Worker)         |
                     |    i7-4790, 32GB       |
                     +------------------------+
```

**Cluster Specifications:**
- 1 control plane + 3 worker nodes
- 104GB total RAM, 14 cores / 28 threads
- 2 NVIDIA GPUs available for compute workloads
- Local NFS storage provisioner
- Self-hosted container registry

## Technologies Demonstrated

| Category | Technologies |
|----------|-------------|
| **Container Orchestration** | Kubernetes (kubeadm), Helm, Kustomize |
| **Configuration Management** | Ansible (roles, playbooks, vault) |
| **Infrastructure Provisioning** | Terraform, Packer (archived) |
| **CI/CD** | GitHub Actions, self-hosted runners |
| **Networking** | Calico CNI, NGINX Ingress, NetBird VPN |
| **Security** | cert-manager, Let's Encrypt, Ansible Vault |
| **Observability** | Prometheus, Grafana (planned) |
| **Container Runtime** | containerd, Docker |

## Repository Structure

```
lab-iac/
|-- ansible/                    # Configuration management
|   |-- inventory/              # Host definitions (control-plane, workers, VPS)
|   |-- group_vars/             # Variables and encrypted secrets
|   |-- playbooks/              # Automation playbooks
|   |-- roles/                  # Reusable Ansible roles
|   `-- templates/              # Jinja2 templates for configs
|
|-- kubernetes/                 # Kubernetes manifests (Kustomize-ready)
|   |-- github-runner/          # Self-hosted Actions runner
|   |-- ingress-nginx/          # Ingress controller config
|   |-- nfs-provisioner/        # Local storage provisioner
|   |-- postgresql/             # Database deployments
|   `-- registry/               # Private container registry
|
|-- docs/                       # Documentation
|   |-- README.md               # Documentation index
|   |-- ARCHITECTURE.md         # System design and decisions
|   |-- DEPLOYMENT.md           # Deployment procedures
|   `-- RUNBOOKS.md             # Operational procedures
|
|-- scripts/                    # Automation scripts
|-- docker/                     # Container build contexts
|-- packer/                     # VM image building (archived)
`-- terraform/                  # Cloud provisioning (archived)
```

## What This Demonstrates

### Infrastructure Automation
- **Idempotent configuration**: Ansible playbooks safely re-runnable
- **Secret management**: Ansible Vault for sensitive data
- **Dynamic inventory**: Automatic host discovery

### Kubernetes Operations
- **Cluster lifecycle**: Automated cluster provisioning with kubeadm
- **GitOps patterns**: Application repos contain their own Helm charts
- **Storage management**: NFS provisioner for persistent volumes
- **Ingress routing**: Domain-based routing with TLS termination

### CI/CD Pipeline
- **Self-hosted runners**: GitHub Actions runners in Kubernetes
- **Private registry**: Push/pull images without external dependencies
- **Automated deployments**: Push to deploy via Helm

### Networking & Security
- **Zero-trust networking**: NetBird VPN for secure connectivity
- **Automatic TLS**: Let's Encrypt with DNS-01 challenges
- **Firewall automation**: nftables rules for K8s traffic

## Quick Start

### Prerequisites
- Ansible 2.9+
- kubectl configured for cluster access
- SSH access to cluster nodes

### Deploy to Existing Cluster
```bash
# Configure an application
cd /path/to/your-app
helm upgrade --install app-name ./helm --wait

# View deployed services
kubectl get ingress -A
```

### Provision New Node
```bash
# Run baseline setup on a new machine
ansible-playbook -i ansible/inventory/all-nodes.yml \
  ansible/playbooks/baseline-setup.yml --limit new-node -v
```

## Documentation

| Document | Description |
|----------|-------------|
| [docs/README.md](docs/README.md) | Documentation index and reading guide |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture and design decisions |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Deployment procedures and patterns |
| [docs/RUNBOOKS.md](docs/RUNBOOKS.md) | Operational runbooks and troubleshooting |
| [ansible/README.md](ansible/README.md) | Ansible configuration guide |

## Archived Components

The `packer/` and `terraform/` directories contain historical work from earlier phases when this lab ran on Proxmox VMs. These are preserved as learning artifacts demonstrating:
- VM template building with Packer
- Infrastructure provisioning with Terraform
- Cloud-init automation

The current focus is bare-metal Kubernetes, which better reflects production environments while reducing resource overhead.

## Active Services

Applications deployed to this cluster (managed in separate repositories):
- **Landing Page**: Static portfolio site
- **Resume Site**: Interactive resume with PostgreSQL backend
- **Coaching Website**: Client-facing business application
- **Family Dashboard**: Household management app

Each application repository contains its own Helm chart following the deployment pattern documented in [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

## License

MIT License - This is a personal learning and portfolio project. Feel free to reference or adapt for your own infrastructure projects.
