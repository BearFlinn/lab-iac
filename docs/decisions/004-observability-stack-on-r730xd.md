# ADR-004: Observability Stack on R730xd

**Date:** 2026-04-01
**Status:** Accepted
**Deciders:** Bear Flinn

## Context

The R730xd has foundation stores (PostgreSQL, Redis, MinIO) deployed as Docker Compose services and monitoring exporters (node_exporter, ipmi_exporter) running with cron-based health checks. There is no central metric collector, log aggregator, or dashboard. The `docs/monitoring-integration.md` documents migration paths to Prometheus/Grafana but nothing is deployed yet.

We need centralized observability to:
- Collect and query metrics from all hosts (currently only per-host cron checks)
- Aggregate logs from Docker containers and system journals
- Accept distributed traces from future application instrumentation
- Provide dashboards for at-a-glance health monitoring

## Decision

Deploy the Grafana LGTM stack (Loki, Grafana, Tempo, Prometheus) plus Alertmanager and Grafana Alloy on the R730xd as Docker Compose services, using the deployed storage backbone.

### Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │              R730xd (<r730xd_ip>)             │
                    │                                             │
                    │  ┌──────────┐   scrape    ┌──────────────┐ │
                    │  │  node    │◄────────────│  Prometheus  │ │
                    │  │ exporter │             │    :9090     │ │
                    │  │  :9100   │             │      │       │ │
                    │  └──────────┘             │      ▼       │ │
                    │  ┌──────────┐             │ Alertmanager │ │
                    │  │   ipmi   │◄────────────│    :9093     │ │
                    │  │ exporter │   scrape    └──────────────┘ │
                    │  │  :9290   │                              │
                    │  └──────────┘                              │
                    │                                            │
                    │  ┌──────────┐  logs    ┌───────┐  chunks  │
                    │  │  Alloy   │─────────►│ Loki  │─────────►│
                    │  │ (docker  │          │ :3100 │  ┌─────┐ │
                    │  │  socket) │          └───────┘  │MinIO│ │
                    │  └──────────┘                     │:9000│ │
                    │                        ┌───────┐  └─────┘ │
                    │                        │ Tempo │─────────►│
                    │                        │ :3200 │  blocks   │
                    │                        └───────┘          │
                    │                                            │
                    │  ┌─────────────────────────────┐          │
                    │  │          Grafana :3000       │          │
                    │  │  datasources: prometheus,    │  ┌─────┐│
                    │  │    loki, tempo               │─►│ PG  ││
                    │  │  dashboards: node exporter,  │  │:5432││
                    │  │    storage health             │  └─────┘│
                    │  └─────────────────────────────┘          │
                    └───────────────────────────────────────────┘
```

### Key Decisions

1. **Separate `/mnt/zfs/observability/` prefix** — not under `/mnt/zfs/foundation/`. These services consume foundation stores; they aren't foundation stores. The filesystem path communicates this distinction. Compose projects live under `/opt/observability/`. All observability data lives on the ZFS pool for low-latency writes (continuous-write workloads are incompatible with SnapRAID).

2. **One Ansible role per service (5 roles)** — `r730xd-prometheus`, `r730xd-loki`, `r730xd-tempo`, `r730xd-grafana`, `r730xd-alloy`. Consistent with ADR-003's pattern of independent roles with independent lifecycles. Exception: Alertmanager is bundled in the Prometheus compose project since they share config and are tightly coupled.

3. **Published ports, not host network** — Observability services are not latency-sensitive like database connections. Published ports avoid conflicts and match the MinIO precedent.

4. **MinIO Obs for Loki/Tempo object storage** — Both services support S3 backends. Uses the dedicated MinIO Obs instance (hot, ZFS-backed, ports 9000/9001) with a service account (not root credentials) scoped to `observability-loki` and `observability-tempo` buckets. A separate MinIO Bulk instance (cold, MergerFS-backed, ports 9002/9003) handles write-once workloads like container registry and build artifacts.

5. **PostgreSQL for Grafana database** — Uses the already-deployed foundation PostgreSQL with a dedicated `grafana` database and user. Avoids running SQLite inside a container.

6. **Grafana Alloy for log collection** — Tails Docker container logs via the Docker socket and pushes to Loki. Simplest approach for a Docker Compose homelab. No per-container logging driver changes needed.

7. **Conservative memory limits** — ~3GB total across all services on a 32GB machine already running foundation stores (~10GB effective). Prometheus 1.5GB, Loki 512MB, Tempo 256MB, Grafana 256MB, Alloy 256MB, Alertmanager 128MB.

8. **No TLS between services** — Consistent with ADR-003. Private LAN (<lab_subnet>).

## Consequences

- **Positive:** Centralized metrics, logs, and traces. Pre-built dashboards for immediate visibility. Alert rules replace cron-based checks for monitored signals.
- **Positive:** Loki/Tempo data durability backed by MinIO Obs on ZFS (checksums, lz4 compression, snapshots).
- **Negative:** 6 additional containers on the R730xd. Memory pressure increases by ~3GB.
- **Negative:** Observability stack itself needs monitoring (meta-monitoring). Prometheus scrapes its own services; Alertmanager watchdog alert covers the "is Prometheus alive" case.
- **Risk:** MinIO Obs availability becomes critical — both Loki and Tempo depend on it for chunk/block storage. Mitigation: local WAL/cache survives brief MinIO outages.

## Alternatives Considered

- **Alloy as Prometheus replacement:** Alloy can scrape and remote-write, but standalone Prometheus is simpler to configure and the scrape configs are already written in monitoring-integration.md.
- **Single compose project for all services:** Rejected for consistency with ADR-003. Independent lifecycle per service is more valuable than deployment convenience.
- **Promtail instead of Alloy:** Promtail is maintenance-mode. Alloy is the recommended replacement and can grow to handle more collection tasks later.
