# Home Lab Infrastructure

Infrastructure as Code for a bare-metal homelab on repurposed enterprise and consumer hardware. The 2026 migration is substantively complete: new Kubernetes cluster is live on dedicated nodes, storage is dynamic (iSCSI + NFS), and apps deploy via GitOps.

**Traffic flow:** Internet → Hetzner VPS (Caddy wildcard TLS) → dedicated WireGuard tunnel → R730xd iptables DNAT → K8s NodePort → ingress-nginx → app ([ADR-019](docs/decisions/019-ingress-and-tls-termination.md))

## Current State

The previous K8s cluster configs are archived (`archive/pre-migration-2026/`). The repo contains only configs for live infrastructure.

**Online:**
- **K8s cluster** — v1.33.10. `dell-inspiron-15` (control plane) + `quanta`, `intel-nuc`, `optiplex` (workers). Cilium CNI, Flux GitOps, democratic-csi for storage, cert-manager, ingress-nginx, ARC v2 runners, Argo Workflows, in-cluster OCI registry. See [docs/k8s-cluster-standup.md](docs/k8s-cluster-standup.md).
- **Dell R730xd** — Storage server (Debian 13, 32 GB ECC, 14 drive bays). Two storage tiers: ZFS raidz1 for latency-sensitive services (Postgres, Redis, MinIO Obs, Prometheus, Loki, Tempo, Grafana), MergerFS + SnapRAID for bulk (MinIO Bulk, NFS for K8s PVCs). Also terminates the VPS → home ingress WireGuard tunnel.
- **Hetzner VPS** — Caddy reverse proxy with wildcard TLS (`*.bearflinn.com` via Cloudflare DNS-01). Routes to the cluster through the WG tunnel.

**In progress / pending:**
- **Tower PC** — will join the cluster as a plain worker ([ADR-021](docs/decisions/021-off-the-shelf-router-tower-pc-as-worker.md)).
- **GPU inference host** — separate new-build machine for standalone inference (Ollama / vLLM / TGI TBD).
- **Off-the-shelf router** — replaces Xfinity gateway routing; unblocks VLAN config on SR2024.
- **Jumpbox (AMD C60 mini PC)** — lightweight command center with Sway, Claude Code, stats display.
- **UPS battery replacement** — APC RS 1500 batteries dead; not blocking anything.

See [docs/migration-2026/](docs/migration-2026/) for full migration plan, hardware inventory, and network design.

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
