# Scripts

Automation scripts for Kubernetes cluster setup, configuration, and management.

## Available Scripts

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `install-cert-manager.sh` | Install cert-manager for TLS certificate management | Initial cluster setup, before installing ingress or GitHub runners |
| `install-github-runner.sh` | Install GitHub Actions Runner Controller via Helm | After cert-manager, when setting up CI/CD |
| `install-ingress-nginx.sh` | Deploy NGINX Ingress Controller with NodePort configuration | After cluster init, for exposing services |
| `install-nfs-provisioner.sh` | Install NFS dynamic PVC provisioner using tower-pc storage | After NFS server setup, for persistent storage |
| `install-postgresql.sh` | Deploy PostgreSQL on tower-pc and configure K8s access | When database services are needed |
| `build-runner-image.sh` | Build and push custom GitHub Actions runner Docker image | When customizing runner with additional tools |
| `configure-insecure-registry.sh` | Configure containerd for self-hosted insecure registry | On each node, when using internal registry |
| `fix-netbird-k8s-forwarding.sh` | Fix NetBird nftables rules for K8s NodePort forwarding | When NetBird blocks K8s traffic |
| `setup-kubeconfig.sh` | Copy kubeconfig from remote cluster to local machine | Initial local development setup |
| `setup-nfs-mount.sh` | Configure NFS mount for tower-pc storage on local machine | For local access to NFS storage |
| `setup-sudoer.sh` | Install sudo and configure sudoer access on remote servers | Initial server provisioning |

## Prerequisites

Most scripts require:
- `kubectl` configured with cluster access
- `helm` (for Helm-based installations)

Some scripts have additional requirements:
- `install-github-runner.sh`: cert-manager must be installed first
- `install-nfs-provisioner.sh`: NFS server running on tower-pc (10.0.0.249)
- `install-postgresql.sh`: Ansible installed, NFS storage available
- `build-runner-image.sh`: Docker with registry access

## Recommended Installation Order

For a new cluster setup:

1. **Cluster initialization** (via Ansible playbooks)
2. `install-cert-manager.sh` - TLS certificate management
3. `install-ingress-nginx.sh` - Ingress controller for HTTP/HTTPS traffic
4. `install-nfs-provisioner.sh` - Dynamic PVC provisioning
5. `install-github-runner.sh` - CI/CD runners (optional)
6. `install-postgresql.sh` - Database server (optional)

## Usage Examples

### Install cert-manager
```bash
./scripts/install-cert-manager.sh
```

### Install NGINX Ingress Controller
```bash
./scripts/install-ingress-nginx.sh
```

### Configure insecure registry on a node
```bash
ssh k8s-worker-1 'bash -s' < ./scripts/configure-insecure-registry.sh 10.0.0.226:32346
```

### Setup local kubeconfig
```bash
./scripts/setup-kubeconfig.sh
# Follow prompts for SSH host and credentials
```

### Fix NetBird forwarding issues
```bash
ssh k8s-control 'sudo bash -s' < ./scripts/fix-netbird-k8s-forwarding.sh
```

## Notes

- Scripts use `set -euo pipefail` for safety
- Most scripts are idempotent and can be run multiple times
- Check script headers for detailed usage information
- NodePorts used by ingress-nginx: HTTP=30487, HTTPS=30356
