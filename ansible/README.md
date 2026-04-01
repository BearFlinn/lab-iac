# Ansible

Configuration management for active infrastructure. Previous K8s cluster and tower-pc configs are in `archive/pre-migration-2026/ansible/`.

## Playbooks

| Playbook | Target | Purpose |
|----------|--------|---------|
| `setup-proxy-vps.yml` | proxy-vps | Caddy reverse proxy on Hetzner VPS (DNS-01 TLS, UDP forwarding) |
| `setup-r730xd.yml` | r730xd | R730xd baseline setup (hostname, static IP, packages, Docker, monitoring) |
| `r730xd-storage.yml` | r730xd | Full storage stack — bay resolution, partitioning, MergerFS pool, SnapRAID parity, NFS exports |
| `deploy-foundation-stores.yml` | r730xd | PostgreSQL 16, Redis 7, MinIO as Docker Compose services on the MergerFS pool |
| `deploy-observability.yml` | r730xd | Prometheus, Alertmanager, Loki, Tempo, Grafana, Alloy on the MergerFS pool |
| `create-staging-vm.yml` | r730xd | Create Debian 13 staging VM via libvirt for critical services during migration |
| `deploy-staging-services.yml` | staging-vm | Deploy web services (landing-page, caz-portfolio, resume-site) to staging VM |
| `setup-claude-user.yml` | various | Restricted read-only SSH access for Claude Code troubleshooting |

## Roles

| Role | Used by | Purpose |
|------|---------|---------|
| `caddy` | setup-proxy-vps.yml | Install Caddy with xcaddy DNS provider plugins |
| `r730xd-storage-prep` | r730xd-storage.yml | Discover HDDs via iDRAC, partition GPT, format ext4, mount by bay |
| `r730xd-mergerfs` | r730xd-storage.yml | Pool data drives into unified mount at `/mnt/pool` |
| `r730xd-snapraid` | r730xd-storage.yml | Parity protection + automated sync/scrub via systemd timers |
| `r730xd-nfs-server` | r730xd-storage.yml | NFS exports of MergerFS pool for K8s PVCs |
| `r730xd-vm-host` | create-staging-vm.yml | KVM/libvirt + bridged networking on R730xd |
| `r730xd-postgres` | deploy-foundation-stores.yml | PostgreSQL 16 on Docker (host network, daily pg_dump backup) |
| `r730xd-redis` | deploy-foundation-stores.yml | Redis 7 on Docker (host network, AOF+RDB persistence) |
| `r730xd-minio` | deploy-foundation-stores.yml | MinIO S3-compatible object storage on Docker |
| `r730xd-prometheus` | deploy-observability.yml | Prometheus + Alertmanager (metrics collection, alerting) |
| `r730xd-loki` | deploy-observability.yml | Loki log aggregation (S3 backend via MinIO) |
| `r730xd-tempo` | deploy-observability.yml | Tempo distributed tracing (S3 backend via MinIO) |
| `r730xd-grafana` | deploy-observability.yml | Grafana dashboards (Postgres backend, provisioned data sources) |
| `r730xd-alloy` | deploy-observability.yml | Grafana Alloy log collector (Docker socket → Loki) |
| `monitoring-base` | setup-r730xd.yml | Node exporter, IPMI exporter, smartd |
| `monitoring-checks` | setup-r730xd.yml | Custom health check scripts (SMART, disks, services, NFS, SnapRAID) |
| `claude-user` | setup-claude-user.yml | Restricted read-only SSH + sudo for troubleshooting |

## Foundation Data Stores

PostgreSQL, Redis, and MinIO run on the R730xd as Docker Compose services, not in K8s. K8s nodes are diskless — all stateful workloads belong on the storage server. See [ADR-003](../docs/decisions/003-foundation-stores-on-r730xd.md) for design rationale.

### Endpoints

| Service | Address | Data Directory |
|---------|---------|----------------|
| PostgreSQL 16 | `postgresql://postgres:<password>@10.0.0.200:5432/` | `/mnt/pool/foundation/postgres/data` |
| Redis 7 | `redis://:<password>@10.0.0.200:6379` | `/mnt/pool/foundation/redis/data` |
| MinIO API | `http://10.0.0.200:9000` | `/mnt/pool/foundation/minio/data` |
| MinIO Console | `http://10.0.0.200:9001` | — |

### Connecting from K8s workloads

K8s pods reach these services at `10.0.0.200:<port>`. Use Kubernetes Secrets or ConfigMaps to pass connection strings — do not hardcode credentials in manifests.

```yaml
# Example: Postgres connection in a K8s deployment
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: foundation-postgres
        key: url
        # value: postgresql://myapp:password@10.0.0.200:5432/myapp
```

### Connecting from staging VM services

The staging VM (192.168.122.191) reaches the R730xd host at its bridge IP. Pass connection strings via Docker Compose environment variables, same as existing staging services.

### Operations

```bash
# Deploy all foundation stores
ansible-playbook -i ansible/inventory/r730xd.yml \
  ansible/playbooks/deploy-foundation-stores.yml \
  --vault-password-file .vault_pass -v

# Deploy a single service
ansible-playbook -i ansible/inventory/r730xd.yml \
  ansible/playbooks/deploy-foundation-stores.yml \
  --vault-password-file .vault_pass --tags postgres -v

# Check service status on R730xd
docker compose -f /opt/foundation/postgres/docker-compose.yml ps
docker compose -f /opt/foundation/redis/docker-compose.yml ps
docker compose -f /opt/foundation/minio/docker-compose.yml ps

# View logs
docker logs foundation-postgres --tail 50
docker logs foundation-redis --tail 50
docker logs foundation-minio --tail 50

# Health checks
docker exec foundation-postgres pg_isready -U postgres
docker exec foundation-redis redis-cli -a <password> ping
curl http://10.0.0.200:9000/minio/health/live
```

### Creating application databases

The playbook deploys Postgres with the superuser only. Create per-application databases as needed:

```bash
docker exec -it foundation-postgres psql -U postgres

# Then in psql:
CREATE USER myapp WITH PASSWORD 'app-password';
CREATE DATABASE myapp OWNER myapp;
```

Store application credentials in Ansible Vault and pass them to K8s via Secrets.

### Backup

- **PostgreSQL:** Daily `pg_dumpall` at 02:00 → `/mnt/pool/foundation/postgres/backup/`, 7-day retention. Cron managed by Ansible.
- **Redis:** AOF (`appendfsync everysec`) + RDB snapshots. Data in `/mnt/pool/foundation/redis/data/`. Copy `dump.rdb` off-host for backup.
- **MinIO:** No automated backup yet. Data on MergerFS with SnapRAID parity. `mc mirror` for offsite replication is a future enhancement.
- **SnapRAID note:** Parity protects against drive failure but is NOT a point-in-time backup — it won't save you from accidental deletion within a sync window.

### Configuration tuning

Default values are in each role's `defaults/main.yml`. Override via `--extra-vars` or by adding variables to the R730xd inventory.

| Variable | Default | Purpose |
|----------|---------|---------|
| `postgres_version` | `"16"` | Postgres Docker image tag |
| `postgres_shared_buffers` | `"2GB"` | Shared memory for caching |
| `postgres_max_connections` | `100` | Max concurrent connections |
| `redis_maxmemory` | `"2gb"` | Memory limit before eviction |
| `redis_maxmemory_policy` | `"allkeys-lru"` | Eviction strategy |
| `minio_api_port` | `9000` | S3 API port |
| `minio_console_port` | `9001` | Web console port |

## Observability Stack

Prometheus, Loki, Tempo, Grafana, and Alloy run on the R730xd as Docker Compose services under `/opt/observability/`. Data persisted on the MergerFS pool under `/mnt/pool/observability/`. See [ADR-004](../docs/decisions/004-observability-stack-on-r730xd.md) for design rationale.

### Endpoints

| Service | Address | Data Directory |
|---------|---------|----------------|
| Prometheus | `http://10.0.0.200:9090` | `/mnt/pool/observability/prometheus/data` |
| Alertmanager | `http://10.0.0.200:9093` | `/mnt/pool/observability/prometheus/alertmanager` |
| Loki | `http://10.0.0.200:3100` | `/mnt/pool/observability/loki/data` |
| Tempo API | `http://10.0.0.200:3200` | `/mnt/pool/observability/tempo/data` |
| Tempo OTLP gRPC | `10.0.0.200:4317` | — |
| Tempo OTLP HTTP | `10.0.0.200:4318` | — |
| Grafana | `http://10.0.0.200:3000` | `/mnt/pool/observability/grafana/data` |

### Operations

```bash
# Deploy entire observability stack
ansible-playbook -i ansible/inventory/r730xd.yml \
  ansible/playbooks/deploy-observability.yml \
  --vault-password-file .vault_pass -v

# Deploy a single service
ansible-playbook -i ansible/inventory/r730xd.yml \
  ansible/playbooks/deploy-observability.yml \
  --vault-password-file .vault_pass --tags grafana -v

# Check service status on R730xd
docker compose -f /opt/observability/prometheus/docker-compose.yml ps
docker compose -f /opt/observability/loki/docker-compose.yml ps
docker compose -f /opt/observability/grafana/docker-compose.yml ps

# View logs
docker logs observability-prometheus --tail 50
docker logs observability-loki --tail 50
docker logs observability-grafana --tail 50

# Health checks
curl http://10.0.0.200:9090/-/healthy
curl http://10.0.0.200:3100/ready
curl http://10.0.0.200:3000/api/health
```

## Inventory

| File | Hosts |
|------|-------|
| `proxy-vps.yml` | Hetzner VPS (SSH port 2222) |
| `r730xd.yml` | Dell R730xd storage server (10.0.0.200) |
| `lab-nodes.yml` | All lab machines (K8s cluster, standalone, staging) |

## Vault secrets

Secrets are in `group_vars/all/vault.yml` (encrypted). See `vault.yml.example` for the full list. The vault password file (`.vault_pass`) must exist at the repo root.

```bash
# View vault contents
ansible-vault view ansible/group_vars/all/vault.yml --vault-password-file .vault_pass

# Edit vault
ansible-vault edit ansible/group_vars/all/vault.yml --vault-password-file .vault_pass
```

## Running playbooks

```bash
# All playbooks use vault — .vault_pass must exist in repo root
ansible-playbook -i ansible/inventory/proxy-vps.yml ansible/playbooks/setup-proxy-vps.yml -v
ansible-playbook -i ansible/inventory/r730xd.yml ansible/playbooks/setup-r730xd.yml -v
ansible-playbook -i ansible/inventory/r730xd.yml ansible/playbooks/r730xd-storage.yml --vault-password-file .vault_pass -v
ansible-playbook -i ansible/inventory/r730xd.yml ansible/playbooks/deploy-foundation-stores.yml --vault-password-file .vault_pass -v
ansible-playbook -i ansible/inventory/r730xd.yml ansible/playbooks/deploy-observability.yml --vault-password-file .vault_pass -v
```
