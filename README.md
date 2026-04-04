# Home Lab Infrastructure

Infrastructure as Code for a bare-metal homelab on repurposed enterprise and consumer hardware. Currently mid-migration to a new topology with dedicated storage, managed switching, and diskless PXE-booted Kubernetes nodes.

**Traffic flow:** Internet → Hetzner VPS (Caddy) → NetBird VPN → Home cluster

## Current State

The previous K8s cluster configs have been archived (`archive/pre-migration-2026/`). The repo now contains only configs for infrastructure that's online or actively being built.

**Online:**
- **Dell R730xd** — Storage server (Debian 13, 32GB ECC, 14 drive bays). Two storage tiers: ZFS raidz1 pool for latency-sensitive services (Postgres, Redis, MinIO Obs, Prometheus, Loki, Tempo, Grafana), MergerFS + SnapRAID for bulk storage (MinIO Bulk, NFS for K8s PVCs). Staging VM for critical services during migration.
- **Hetzner VPS** — Caddy reverse proxy with wildcard TLS (*.bearflinn.com via Cloudflare DNS-01). Routes traffic over NetBird VPN to the cluster.

**In progress:**
- Jumpbox (AMD C60 mini PC) — Lightweight command center with Sway, Claude Code, stats display
- K8s cluster rebuild — New topology with diskless nodes, VLANs, dedicated storage network

See [docs/migration-2026/](docs/migration-2026/) for the full migration plan, hardware inventory, and network design.

## Repository Structure

```
ansible/           Playbooks, roles, and inventory for active infrastructure
configs/           Machine-specific configs (jumpbox desktop, R730xd preseed)
scripts/           Shell scripts for R730xd setup and jumpbox image building
docs/              Migration planning documentation
archive/           Previous cluster configs (preserved directory structure)
```

## Quick Start

```bash
# All playbooks decrypt secrets via .vault_pass (git-ignored)

# R730xd storage server
ansible-playbook -i ansible/inventory/r730xd.yml ansible/playbooks/setup-r730xd.yml -v
ansible-playbook -i ansible/inventory/r730xd.yml ansible/playbooks/r730xd-storage.yml --vault-password-file .vault_pass -v
ansible-playbook -i ansible/inventory/r730xd.yml ansible/playbooks/deploy-foundation-stores.yml --vault-password-file .vault_pass -v
ansible-playbook -i ansible/inventory/r730xd.yml ansible/playbooks/deploy-observability.yml --vault-password-file .vault_pass -v

# Hetzner VPS proxy
ansible-playbook -i ansible/inventory/proxy-vps.yml ansible/playbooks/setup-proxy-vps.yml -v
```

## Documentation

| Document | Contents |
|----------|----------|
| [docs/migration-2026/migration-plan.md](docs/migration-2026/migration-plan.md) | Migration phases, dependency graph, risk register |
| [docs/migration-2026/current-hardware-inventory.md](docs/migration-2026/current-hardware-inventory.md) | All hardware specs and current roles |
| [docs/migration-2026/network-target.md](docs/migration-2026/network-target.md) | Target network design with VLANs |
| [docs/decisions/003-foundation-stores-on-r730xd.md](docs/decisions/003-foundation-stores-on-r730xd.md) | Why Postgres/Redis/MinIO run on R730xd as separate Docker Compose projects |
| [docs/decisions/004-observability-stack-on-r730xd.md](docs/decisions/004-observability-stack-on-r730xd.md) | Why Prometheus/Loki/Tempo/Grafana run on R730xd with MinIO + Postgres backends |
| [archive/pre-migration-2026/README.md](archive/pre-migration-2026/README.md) | Index of archived configs with reusable items flagged |

## License

MIT
