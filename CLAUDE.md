# Repository Overview

Bare-metal Kubernetes portfolio project on repurposed hardware. Four physical machines connected via NetBird VPN to a Hetzner VPS proxy.

**Traffic flow:** Internet → Hetzner VPS (Caddy) → NetBird VPN → Home cluster

# Common Commands

## Ansible Playbooks

```bash
# All playbooks use vault - .vault_pass must exist in repo root (git-ignored)
ansible-playbook -i ansible/inventory/all-nodes.yml ansible/playbooks/<playbook>.yml -v

# For proxy-vps playbooks (requires vault for Cloudflare token)
ansible-playbook -i ansible/inventory/proxy-vps.yml ansible/playbooks/setup-proxy-vps.yml -v
```

Key playbooks in execution order for new cluster:
1. `baseline-setup.yml` - OS setup per machine
2. `setup-control-plane.yml` - kubeadm init + Calico
3. `setup-workers.yml` - join workers
4. `k8s-verify.yml` - health validation
5. `setup-proxy-vps.yml` - configure VPS proxy

## Kubernetes Operations

```bash
# Set kubeconfig for local kubectl
export KUBECONFIG=~/.kube/lab-k8s-config

# Deploy Kustomize manifests
kubectl apply -k kubernetes/base

# Infrastructure scripts (idempotent, safe to re-run)
./scripts/install-cert-manager.sh
./scripts/install-ingress-nginx.sh
./scripts/install-nfs-provisioner.sh
```

# Architecture

## Cluster Nodes

| Node | IP | Role | Notable |
|------|----|------|---------|
| dell-inspiron-15 | 10.0.0.226 | Control plane | 8GB RAM (resource-constrained) |
| tower-pc | 10.0.0.249 | Worker | NFS server, PostgreSQL, 9.3TB storage |
| msi-laptop | Worker | Monitoring workloads | GTX 1060 GPU |
| dell-optiplex-9020 | Worker | General compute | |

## Key Network Details

- Pod CIDR: `10.244.0.0/16`
- Service CIDR: `10.96.0.0/12`
- Ingress NodePorts: HTTP `30487`, HTTPS `30356`
- Container registry: `10.0.0.226:32346` (insecure)
- NFS export: `10.0.0.249:/mnt/nfs-storage`

## Technology Stack

- **Orchestration:** Kubernetes 1.31 via kubeadm, Calico CNI
- **Config management:** Ansible with vault-encrypted secrets
- **Storage:** NFS dynamic provisioner on tower-pc
- **TLS:** cert-manager with Let's Encrypt (DNS-01 via Cloudflare)
- **Ingress:** NGINX Ingress Controller
- **External proxy:** Caddy on Hetzner VPS

# Repository Structure

```
ansible/
├── inventory/all-nodes.yml      # Master inventory with hardware specs
├── group_vars/all/vault.yml     # Encrypted secrets (Cloudflare token)
├── group_vars/k8s_cluster.yml   # K8s versions, CIDR ranges
├── playbooks/                   # 14 playbooks
└── roles/                       # Reusable components

kubernetes/
├── base/                        # Kustomize manifests (registry, github-runner, postgresql)
├── ingress-nginx/values.yaml    # Helm values
└── nfs-provisioner/values.yaml  # Helm values

scripts/                         # Shell scripts (set -euo pipefail, idempotent)
docs/                            # ARCHITECTURE.md, DEPLOYMENT.md, RUNBOOKS.md
```

# Secrets Management

- **Ansible Vault:** `group_vars/all/vault.yml` encrypted, decrypted via `.vault_pass` file
- **Vault password file:** Must exist at repo root, git-ignored
- **K8s secrets:** Managed via CI/CD pipelines in application repos

# Deployment Pattern

Applications use GitOps: push to main → GitHub Actions builds image → pushes to registry (10.0.0.226:32346) → deploys via Helm. Self-hosted runners in cluster handle CI/CD.

# Important Instructions

- Any and all configuration or infrastructures MUST be conducted with IaC.
- If any changes cannot be conducted via IaC, they must be clearly documented.