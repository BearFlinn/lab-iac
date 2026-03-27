# Ansible

Configuration management for active infrastructure. Previous K8s cluster and tower-pc configs are in `archive/pre-migration-2026/ansible/`.

## Playbooks

| Playbook | Target | Purpose |
|----------|--------|---------|
| `setup-proxy-vps.yml` | proxy-vps | Caddy reverse proxy on Hetzner VPS (DNS-01 TLS, UDP forwarding) |
| `setup-r730xd.yml` | r730xd | R730xd baseline setup (hostname, static IP, firewall, storage packages) |
| `r730xd-storage-prep.yml` | r730xd | Auto-discover and prepare R730xd data drives (partition, format, mount) |

## Roles

| Role | Used by | Purpose |
|------|---------|---------|
| `caddy` | setup-proxy-vps.yml | Install Caddy with xcaddy DNS provider plugins |
| `r730xd-storage-prep` | r730xd-storage-prep.yml | Discover HDDs, partition as GPT, format ext4, mount |

## Inventory

| File | Hosts |
|------|-------|
| `proxy-vps.yml` | Hetzner VPS (SSH port 2222) |
| `r730xd.yml` | Dell R730xd storage server (10.0.0.200) |
| `proxy-vps-wildcard.yml.example` | Template for wildcard proxy inventory |

## Running playbooks

```bash
# All playbooks use vault - .vault_pass must exist in repo root
ansible-playbook -i ansible/inventory/proxy-vps.yml ansible/playbooks/setup-proxy-vps.yml -v
ansible-playbook -i ansible/inventory/r730xd.yml ansible/playbooks/setup-r730xd.yml -v
ansible-playbook -i ansible/inventory/r730xd.yml ansible/playbooks/r730xd-storage-prep.yml -v
```
