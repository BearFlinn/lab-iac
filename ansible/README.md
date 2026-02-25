# Ansible Configuration Management

This directory contains Ansible playbooks, roles, and inventory for automating the Kubernetes cluster and supporting infrastructure.

## Overview

Ansible handles:
- Base machine configuration (static IPs, hostnames, packages)
- Kubernetes cluster deployment (control plane, workers)
- VPS proxy configuration (Caddy, TLS certificates)
- Operational fixes and maintenance tasks

## Directory Structure

```
ansible/
|-- ansible.cfg              # Ansible configuration
|-- inventory/               # Host definitions
|   |-- all-nodes.yml        # All cluster nodes
|   |-- control-plane.yml    # Control plane only
|   |-- proxy-vps.yml        # VPS proxy server
|   |-- host_vars/           # Per-host variables
|   `-- single-host/         # Templates for individual setup
|
|-- group_vars/              # Group variables
|   |-- all/
|   |   |-- vars.yml         # Common variables
|   |   `-- vault.yml        # Encrypted secrets (Cloudflare token)
|   `-- k8s_cluster.yml      # Kubernetes configuration
|
|-- playbooks/               # Automation playbooks
|-- roles/                   # Reusable roles
`-- templates/               # Jinja2 templates
```

## Available Playbooks

| Playbook | Description | Target |
|----------|-------------|--------|
| `baseline-setup.yml` | Initial machine setup (static IP, hostname, packages) | Cluster nodes |
| `setup-control-plane.yml` | Deploy K8s control plane with kubeadm | Control plane |
| `setup-workers.yml` | Join worker nodes to cluster | Worker nodes |
| `k8s-verify.yml` | Verify cluster health | Control plane |
| `setup-proxy-vps.yml` | Configure VPS with Caddy, TLS, and K8s ingress proxy | Proxy VPS |
| `configure-registry.yml` | Configure insecure registry on nodes | Cluster nodes |
| `fix-netbird-k8s.yml` | Fix nftables rules for NetBird | Control plane |
| `setup-cert-manager.yml` | Deploy cert-manager to cluster | Control plane |
| `setup-nfs-provisioner.yml` | Deploy NFS storage provisioner | Control plane |
| `setup-postgresql.yml` | Deploy PostgreSQL database | Control plane |
| `tower-storage-setup.yml` | Configure storage on tower-pc | Tower PC |
| `reset-cluster.yml` | Reset Kubernetes cluster (destructive) | All nodes |

## Available Roles

| Role | Description |
|------|-------------|
| `k8s-prerequisites` | Kernel modules, containerd, CNI plugins |
| `k8s-packages` | kubeadm, kubelet, kubectl installation |
| `k8s-control-plane` | kubeadm init, Calico CNI, kubeconfig |
| `k8s-worker` | Join workers to cluster |
| `caddy` | Caddy web server with TLS and DNS plugins |
| `postgresql-server` | PostgreSQL database server |
| `tower-storage-setup` | Storage configuration for tower-pc |

## Quick Start

### Set Up a New Machine

```bash
# For control plane (uses existing inventory)
ansible-playbook -i inventory/control-plane.yml playbooks/baseline-setup.yml -v

# For worker nodes (use single-host template)
cp inventory/single-host/template.yml /tmp/new-node.yml
# Edit /tmp/new-node.yml with hostname and IP
ansible-playbook -i /tmp/new-node.yml playbooks/baseline-setup.yml -v
```

### Deploy Kubernetes Cluster

```bash
# Step 1: Deploy control plane
ansible-playbook -i inventory/control-plane.yml playbooks/setup-control-plane.yml -v

# Step 2: Join workers
ansible-playbook -i inventory/all-nodes.yml playbooks/setup-workers.yml -v

# Step 3: Verify cluster
ansible-playbook -i inventory/control-plane.yml playbooks/k8s-verify.yml -v
```

### Configure VPS Proxy

```bash
# Initial VPS setup with Caddy
ansible-playbook -i inventory/proxy-vps.yml playbooks/setup-proxy-vps.yml \
  --vault-password-file ../.vault_pass -v

# Update K8s routes
ansible-playbook -i inventory/proxy-vps.yml playbooks/configure-vps-k8s-routes.yml -v
```

## Inventory Configuration

### Control Plane (`inventory/control-plane.yml`)

```yaml
all:
  children:
    k8s_control_plane:
      hosts:
        dell-inspiron-15:
          ansible_host: 10.0.0.226
          ansible_user: bearf
```

### All Nodes (`inventory/all-nodes.yml`)

Contains all cluster nodes with their specifications:
- `k8s_control_plane` group: Dell Inspiron 15
- `k8s_workers` group: MSI Laptop, Tower PC, Dell Optiplex
- Node labels and roles defined per host

### Proxy VPS (`inventory/proxy-vps.yml`)

```yaml
all:
  hosts:
    proxy-vps-1:
      ansible_host: proxy-vps
      ansible_user: bearf
      ansible_port: 2222

      caddy_root_domain: "bearflinn.com"
      caddy_dns_provider: "cloudflare"
      k8s_ingress_endpoint: "100.96.94.27:30487"
```

## Secrets Management with Ansible Vault

### Setup (One-Time)

```bash
# Create vault password
openssl rand -base64 32 > ../.vault_pass
chmod 600 ../.vault_pass

# Create vault file from example
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
vim group_vars/all/vault.yml  # Add real Cloudflare token

# Encrypt vault
ansible-vault encrypt group_vars/all/vault.yml --vault-password-file ../.vault_pass
```

### Using Vault

```bash
# Run playbook with vault
ansible-playbook -i inventory/proxy-vps.yml playbooks/setup-proxy-vps.yml \
  --vault-password-file ../.vault_pass -v

# View encrypted content
ansible-vault view group_vars/all/vault.yml --vault-password-file ../.vault_pass

# Edit encrypted content
ansible-vault edit group_vars/all/vault.yml --vault-password-file ../.vault_pass
```

### Security Notes

- `.vault_pass` is in `.gitignore` - never commit
- `vault.yml` is encrypted - safe to commit
- Share vault password securely with team members

## Cloudflare DNS-01 Setup

For wildcard TLS certificates, you need a Cloudflare API token.

### Get Cloudflare Token

1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Click "Create Token"
3. Use "Edit zone DNS" template
4. Select your zone (e.g., `bearflinn.com`)
5. Create and copy the token

### Configure Vault

```yaml
# group_vars/all/vault.yml (before encryption)
vault_cloudflare_api_token: "your-cloudflare-api-token"
```

### Verify Setup

```bash
# After running proxy-vps playbook, verify certificate
echo | openssl s_client -servername test.bearflinn.com \
  -connect test.bearflinn.com:443 2>/dev/null | \
  openssl x509 -noout -text | grep -A2 "Subject Alternative Name"

# Should show: DNS:*.bearflinn.com, DNS:bearflinn.com
```

## Baseline Setup Details

The `baseline-setup.yml` playbook configures individual machines:

### What It Does

1. **Package Installation**: curl, wget, git, vim, htop, net-tools, nfs-common
2. **Hostname Configuration**: Sets hostname from inventory name
3. **Static IP Configuration**: Auto-detects and makes current IP static
4. **DNS Configuration**: Sets custom DNS servers (8.8.8.8, 8.8.4.4)
5. **Cluster Hosts File**: Adds all cluster nodes to /etc/hosts
6. **System Tweaks**: Disables auto-updates, sets timezone

### Key Feature: Auto-Static IP

The playbook automatically makes whatever IP the machine currently has into a static IP:
- No need to specify target IPs manually
- Auto-detects: current IP, gateway, subnet mask, network interface
- Override with `static_ip` variable if needed

### Usage

```bash
# Using control-plane inventory
ansible-playbook -i inventory/control-plane.yml playbooks/baseline-setup.yml -v

# Using single-host template for workers
cp inventory/single-host/template.yml /tmp/tower-pc.yml
vim /tmp/tower-pc.yml  # Edit with actual values
ansible-playbook -i /tmp/tower-pc.yml playbooks/baseline-setup.yml -v
rm /tmp/tower-pc.yml
```

## Kubernetes Control Plane Setup

The `setup-control-plane.yml` playbook deploys Kubernetes:

### Prerequisites

- SSH key-based authentication to control plane
- Baseline setup completed
- Network connectivity between nodes

### What It Does

1. **Prerequisites Role**: Kernel modules, containerd, CNI plugins
2. **Packages Role**: Install kubeadm, kubelet, kubectl
3. **Control Plane Role**: Run kubeadm init, deploy Calico, configure kubeconfig

### Configuration

Edit `group_vars/k8s_cluster.yml`:

```yaml
kubernetes_version: "1.31"
pod_network_cidr: "10.244.0.0/16"
calico_version: "v3.28.0"
```

### Post-Setup

```bash
# Access cluster from control plane
ssh bearf@10.0.0.226
kubectl get nodes

# Copy kubeconfig locally
scp bearf@10.0.0.226:~/.kube/config ~/.kube/lab-k8s-config
export KUBECONFIG=~/.kube/lab-k8s-config
```

## VPS Proxy Setup

The `setup-proxy-vps.yml` playbook configures the Hetzner VPS:

### What It Deploys

- **Caddy Web Server**: With Cloudflare DNS plugin for DNS-01
- **UFW Firewall**: Ports 2222 (SSH), 80, 443
- **Wildcard Certificates**: Automatic TLS for all subdomains

### Architecture

```
Internet -> VPS (Caddy) -> NetBird VPN -> K8s Ingress
```

### K8s Routes Configuration

The VPS routes all `*.bearflinn.com` traffic (not matched by a specific `caddy_services` entry) to the K8s ingress via NetBird. The ingress controller handles subdomain routing and returns 404 for unconfigured services.

```yaml
k8s_ingress_endpoint: "100.96.94.27:30487"
caddy_root_domain: "bearflinn.com"
```

## Cluster Setup Workflow

Complete workflow from fresh machines to running cluster:

### Phase 0: Baseline Setup (Per Machine)

```bash
# Control plane
ansible-playbook -i inventory/control-plane.yml playbooks/baseline-setup.yml -v

# Each worker (one at a time)
cp inventory/single-host/template.yml /tmp/worker.yml
# Edit with hostname and IP
ansible-playbook -i /tmp/worker.yml playbooks/baseline-setup.yml -v
```

### Phase 1: Kubernetes Cluster

```bash
# Deploy control plane
ansible-playbook -i inventory/control-plane.yml playbooks/setup-control-plane.yml -v

# Join workers
ansible-playbook -i inventory/all-nodes.yml playbooks/setup-workers.yml -v

# Verify
ssh bearf@10.0.0.226 kubectl get nodes
```

### Phase 2: External Access

```bash
# Configure VPS proxy
ansible-playbook -i inventory/proxy-vps.yml playbooks/setup-proxy-vps.yml \
  --vault-password-file ../.vault_pass -v

# Configure K8s routes
ansible-playbook -i inventory/proxy-vps.yml playbooks/configure-vps-k8s-routes.yml -v
```

## Troubleshooting

### Connectivity Issues

```bash
# Test Ansible connectivity
ansible -i inventory/all-nodes.yml all -m ping

# Verbose output
ansible -i inventory/all-nodes.yml all -m ping -vvv
```

### Vault Issues

```bash
# Vault password not found
# Ensure .vault_pass exists at repo root

# Cannot decrypt
ansible-vault view group_vars/all/vault.yml --vault-password-file ../.vault_pass
```

### Calico BGP Issues

If Calico pods show 0/1 Running:

```bash
# Verify IP autodetection patch
kubectl get ds calico-node -n kube-system -o yaml | grep -A5 "IP_AUTODETECTION_METHOD"

# Should show: can-reach=8.8.8.8
# Force pod restart if needed
kubectl delete pods -n kube-system -l k8s-app=calico-node
```

### NetBird Forwarding Issues

```bash
# Run fix playbook
ansible-playbook -i inventory/control-plane.yml playbooks/fix-netbird-k8s.yml -v

# Or run script directly
ssh bearf@10.0.0.226 "sudo /path/to/scripts/fix-netbird-k8s-forwarding.sh"
```

## Common Commands

```bash
# Run playbook with verbose output
ansible-playbook -i inventory/all-nodes.yml playbooks/baseline-setup.yml -v

# Dry run (check mode)
ansible-playbook -i inventory/all-nodes.yml playbooks/baseline-setup.yml --check -v

# Limit to specific hosts
ansible-playbook -i inventory/all-nodes.yml playbooks/baseline-setup.yml --limit tower-pc -v

# Run specific tags
ansible-playbook -i inventory/all-nodes.yml playbooks/baseline-setup.yml --tags hosts -v

# List available tags
ansible-playbook -i inventory/all-nodes.yml playbooks/baseline-setup.yml --list-tags
```

## Related Documentation

- [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) - Cluster architecture
- [docs/DEPLOYMENT.md](../docs/DEPLOYMENT.md) - Application deployment
- [docs/RUNBOOKS.md](../docs/RUNBOOKS.md) - Operational procedures
