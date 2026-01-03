# Kubernetes Infrastructure

This directory contains Kubernetes manifests and configurations for the lab cluster.

## Directory Structure

```
kubernetes/
├── base/                           # Kustomize base configurations
│   ├── kustomization.yaml          # Root kustomization
│   ├── registry/                   # Private Docker registry
│   ├── github-runner/              # GitHub Actions runners
│   └── postgresql/                 # External PostgreSQL service
├── overlays/                       # Environment-specific configurations
│   └── production/                 # Production overlay
├── github-runner/                  # Helm values for actions-runner-controller
├── ingress-nginx/                  # NGINX Ingress Controller (Helm-based)
└── nfs-provisioner/                # NFS storage provisioner (Helm-based)
```

## Component Overview

### Kustomize-Managed Components

These components are deployed using Kustomize and can be customized via overlays:

| Component | Namespace | Description |
|-----------|-----------|-------------|
| **registry** | `registry` | Private Docker registry for container images |
| **github-runner** | `actions-runner-system` | Self-hosted GitHub Actions runners with auto-scaling |
| **postgresql** | `database` | External PostgreSQL service endpoint (tower-pc) |

### Helm-Managed Components

These components are installed via Helm charts:

| Component | Namespace | Chart |
|-----------|-----------|-------|
| **ingress-nginx** | `ingress-nginx` | Official NGINX Ingress Controller |
| **nfs-provisioner** | `nfs-provisioner` | NFS Subdir External Provisioner |
| **actions-runner-controller** | `actions-runner-system` | GitHub Actions Runner Controller |

## Deployment

### Deploy All Kustomize Components

```bash
# Deploy base configuration (all components)
kubectl apply -k kubernetes/base

# Deploy with production overlay
kubectl apply -k kubernetes/overlays/production
```

### Deploy Individual Components

```bash
# Registry
kubectl apply -k kubernetes/base/registry

# GitHub Actions runners
kubectl apply -k kubernetes/base/github-runner

# PostgreSQL external service
kubectl apply -k kubernetes/base/postgresql
```

### Helm Components

For Helm-managed components, refer to their respective READMEs:

```bash
# NGINX Ingress Controller
./scripts/install-ingress-nginx.sh

# NFS Provisioner
helm install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  -n nfs-provisioner --create-namespace \
  -f kubernetes/nfs-provisioner/values.yaml

# GitHub Actions Runner Controller
helm install actions-runner-controller actions-runner-controller/actions-runner-controller \
  -n actions-runner-system --create-namespace \
  -f kubernetes/github-runner/values.yaml
```

## Deployment Order

For a fresh cluster, deploy components in this order:

1. **NFS Provisioner** - Required for persistent storage
2. **Ingress NGINX** - Required for external traffic routing
3. **Registry** - Depends on NFS storage
4. **PostgreSQL** - External service, no dependencies
5. **GitHub Runners** - Depends on registry (for custom runner images)

## Component Details

### Registry

Private Docker registry for storing container images built in the cluster.

- **Storage**: 50Gi NFS-backed PVC
- **Access**: NodePort 32346
- **Features**: Image deletion enabled

See: `base/registry/` manifests

### GitHub Actions Runners

Self-hosted runners for GitHub Actions with Docker-in-Docker support.

- **Scaling**: 1-4 runners based on utilization
- **Labels**: `self-hosted`, `kubernetes`, `linux`, `lab`
- **Features**: Docker build capability, custom runner image

See: `base/github-runner/README.md`

### PostgreSQL

External PostgreSQL 16 with pgvector running on tower-pc.

- **Host**: tower-pc (10.0.0.249)
- **Features**: TLS, pgvector extension
- **Access**: `postgresql.database.svc.cluster.local:5432`

See: `base/postgresql/README.md`

### Ingress NGINX

NGINX Ingress Controller for bare-metal deployment.

- **HTTP NodePort**: 30487
- **HTTPS NodePort**: 30356
- **IngressClass**: `nginx` (default)

See: `ingress-nginx/README.md`

### NFS Provisioner

Dynamic NFS storage provisioner using tower-pc NFS server.

- **StorageClass**: `nfs-client` (default)
- **NFS Server**: 10.0.0.249
- **Export Path**: `/mnt/nfs-storage`

See: `nfs-provisioner/values.yaml`

## Verification

```bash
# Verify Kustomize build (dry-run)
kubectl kustomize kubernetes/base
kubectl kustomize kubernetes/overlays/production

# Check deployed resources
kubectl get all -n registry
kubectl get all -n actions-runner-system
kubectl get all -n database
kubectl get all -n ingress-nginx
kubectl get all -n nfs-provisioner

# Check storage
kubectl get pvc -A
kubectl get storageclass
```

## Troubleshooting

### Kustomize Build Errors

```bash
# Validate kustomization files
kubectl kustomize kubernetes/base --enable-helm 2>&1

# Check individual components
kubectl kustomize kubernetes/base/registry
kubectl kustomize kubernetes/base/github-runner
kubectl kustomize kubernetes/base/postgresql
```

### Component-Specific Issues

Refer to the README files in each component directory for detailed troubleshooting guides.
