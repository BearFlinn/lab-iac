# ADR-003: Foundation Data Stores on R730xd

**Date:** 2026-04-01
**Status:** Accepted

## Context

The lab architecture places all stateful workloads on the R730xd storage server. K8s nodes are diskless (PXE boot) and treat compute as disposable. Services that need durable state — PostgreSQL, Redis, MinIO — must run on the R730xd, with K8s workloads connecting over the LAN at `10.0.0.200:<port>`.

Several design choices needed to be made about how to organize, deploy, and persist these services.

## Decisions

### Separate roles, not a single "foundation-stores" role

Each service gets its own Ansible role (`r730xd-postgres`, `r730xd-redis`, `r730xd-minio`). They have different configuration concerns (Postgres tuning vs Redis memory policy vs MinIO bucket setup), different upgrade cadences, and independent lifecycles. A single role would create artificial coupling. This follows the existing pattern where each `r730xd-*` role is one responsibility.

### Separate Docker Compose projects per service

Each role deploys its own `docker-compose.yml` under `/opt/foundation/<service>/`. This gives independent `docker compose up/down/restart/logs` per service. No risk of one compose operation pulling down another service.

### Host network for Postgres and Redis, published ports for MinIO

Postgres and Redis use `network_mode: host`. Simplest path for LAN clients to reach `10.0.0.200:5432` and `10.0.0.200:6379` — no NAT overhead, real client IPs in logs. MinIO uses published ports (`9000:9000`, `9001:9001`) to keep the API and console ports cleanly separated.

### Data on MergerFS pool

All service data lives under `/mnt/pool/foundation/<service>/`. MergerFS adds a FUSE layer, but its fsync pass-through is reliable at homelab scale. The pool's flexibility (spanning multiple drives, balanced writes) outweighs the marginal overhead. If Postgres performance becomes an issue, data can be moved to a direct bay mount later without changing the role — just override `postgres_data_dir`.

### Postgres backup via pg_dump cron

SnapRAID protects against drive failure but is not a point-in-time backup (syncs are periodic, no protection against accidental deletion within a sync window). A daily `pg_dumpall` with 7-day rotation provides a basic safety net. Redis has built-in AOF/RDB persistence. MinIO backup (e.g., `mc mirror`) deferred to a follow-up.

## Trade-offs

- **Host network limits port flexibility.** If two Postgres instances are needed, one must use a non-default port. Acceptable — a single shared Postgres is the intended pattern.
- **No TLS between services.** Traffic is on a private LAN (`10.0.0.0/24`). TLS can be added later if the threat model changes.
- **Docker volumes vs bind mounts.** We use bind mounts to `/mnt/pool/foundation/...` rather than Docker named volumes. This makes the data location explicit and visible to SnapRAID, backup scripts, and operators browsing the filesystem.
