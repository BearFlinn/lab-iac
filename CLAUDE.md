# Repository Overview

Homelab Infrastructure as Code, mid-migration to new hardware. Previous K8s cluster configs are archived in `archive/pre-migration-2026/` with original directory structure preserved.

**Active infrastructure:**
- **R730xd** (10.0.0.200) — Storage server, Debian 13, iDRAC at 10.0.0.203
- **Hetzner VPS** (proxy-vps) — Caddy reverse proxy, NetBird VPN endpoint
- **Jumpbox** — AMD C60 mini PC, lightweight command center (in progress)

**Migration in progress:** See `docs/migration-2026/` for full plan, hardware inventory, and network design.

# Common Commands

## Ansible Playbooks

```bash
# All playbooks use vault - .vault_pass must exist in repo root (git-ignored)
ansible-playbook -i ansible/inventory/r730xd.yml ansible/playbooks/setup-r730xd.yml -v
ansible-playbook -i ansible/inventory/r730xd.yml ansible/playbooks/r730xd-storage-prep.yml -v
ansible-playbook -i ansible/inventory/proxy-vps.yml ansible/playbooks/setup-proxy-vps.yml -v
```

## Scripts

```bash
# R730xd setup (idempotent)
./scripts/build-r730xd-iso.sh        # Build preseeded Debian ISO
./scripts/configure-r730xd-jbod.sh   # Configure PERC H730 for JBOD via iDRAC

# Jumpbox
./scripts/build-jumpbox-image.sh     # Build Debian Trixie image
```

# Architecture

## Active Machines

| Node | IP | Role | Notable |
|------|----|------|---------|
| r730xd | 10.0.0.200 | Storage server | Debian 13, 32GB ECC, 12x 3.5" + 2x 2.5" bays, iDRAC 10.0.0.203 |
| proxy-vps | Hetzner | Reverse proxy | Caddy, NetBird VPN, SSH port 2222 |
| msi-laptop | 10.0.0.177 | Dev/management | Not in cluster, used for managing infra |

## Machines Pending Migration

See `docs/migration-2026/current-hardware-inventory.md` for full specs.

- **dell-inspiron-15** (10.0.0.226) — Current K8s control plane, will become diskless PXE node
- **tower-pc** (10.0.0.249) — Current K8s worker/NFS, will become GPU inference workstation
- **dell-optiplex-9020** — Current deb-web server, will become diskless K8s worker
- **Quanta QSSC-2ML** — New server, will be diskless K8s worker

# Repository Structure

```
ansible/
├── inventory/{proxy-vps.yml, r730xd.yml}
├── group_vars/all/{vars.yml, vault.yml}
├── playbooks/{setup-proxy-vps.yml, setup-r730xd.yml, r730xd-storage-prep.yml}
└── roles/{caddy/, r730xd-storage-prep/}

configs/
├── jumpbox/{sway/, waybar/, foot/}
└── r730xd/preseed.cfg

scripts/{build-r730xd-iso.sh, configure-r730xd-jbod.sh, build-jumpbox-image.sh}
docs/migration-2026/                  # Active planning docs
archive/pre-migration-2026/           # Previous cluster configs (preserved structure)
```

# Secrets Management

- **Ansible Vault:** `group_vars/all/vault.yml` encrypted, decrypted via `.vault_pass` file
- **Vault password file:** Must exist at repo root, git-ignored

# Important Instructions

- Any and all configuration or infrastructures MUST be conducted with IaC.
- If any changes cannot be conducted via IaC, they must be clearly documented.
- Warnings are blockers and MUST be resolved before considering work complete. If a warning is expected and truly cannot be resolved, it must be clearly documented with an explanation of why.
