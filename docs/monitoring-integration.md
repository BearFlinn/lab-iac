# Monitoring Integration Guide

> **IP addresses:** Authoritative values are in `ansible/group_vars/all/network.yml`.

How the homelab monitoring system works today, and how to evolve it as the lab grows.

## Current Architecture

The monitoring system uses two Ansible roles applied to each monitored machine:

- **`monitoring-base`** — installs packages and Prometheus exporters (node\_exporter on `:9100`, ipmi\_exporter on `:9290`), configures smartd for SMART health monitoring and self-tests
- **`monitoring-checks`** — deploys cron-based health check scripts that alert on critical conditions and write Prometheus-compatible metrics to the node\_exporter textfile collector

The central observability stack (Prometheus, Loki, Tempo, Grafana, Alloy) is deployed on the R730xd via `deploy-observability.yml`. See [ADR-004](decisions/004-observability-stack-on-r730xd.md) for design decisions. Prometheus scrapes all exporters; Alloy collects Docker container logs and ships to Loki; Grafana provides dashboards and cross-linked data sources.

Cron-based health checks continue to run as a belt-and-suspenders layer alongside Prometheus alerting.

### What runs where

| Component | Location | Port | Purpose |
|-----------|----------|------|---------|
| node\_exporter | Each host | 9100 | System metrics (CPU, RAM, disk I/O, network) |
| ipmi\_exporter | Hosts with BMC | 9290 | Hardware sensors (PSU, fans, temps, ECC) |
| smartd | Each host | — | Drive self-tests, SMART monitoring |
| Cron checks | Each host | — | Tier 1 (every 5m) + Tier 2 (every 15m) health checks |
| Textfile metrics | Each host | — | `.prom` files at `/var/lib/prometheus/node-exporter/` |

### Tempo tenants

Tempo runs in multi-tenant mode. Every OTLP write and every Grafana query
must set `X-Scope-OrgID`; tenant-less requests are rejected.

| Tenant | Purpose |
|---|---|
| `grizzly-platform` | Homelab operational traces — Argo Workflows, future self-instrumented services, and the `feedback-ingest` service's own operational traces. Default for new producers. |
| `residuum-feedback` | Report traces emitted by the `feedback-ingest` service. Isolated so feedback volume can't affect platform trace retention or queries. |

Grafana exposes both as separate datasources: `Tempo (grizzly-platform)`
(uid `tempo` — preserved so Prometheus exemplar links and Loki derived
fields continue to resolve) and `Tempo (residuum-feedback)` (uid
`tempo-residuum-feedback`). Add a new tenant only when there's a specific
isolation reason; default new producers to `grizzly-platform`.

### Check scripts

Located at `/usr/local/lib/monitoring/checks/` on each host:

| Script | Tier | What it checks |
|--------|------|----------------|
| `check-smart.sh` | 1 | SMART health, drive temps, reallocated sectors |
| `check-disks.sh` | 1 | Disk space usage on all mounts |
| `check-services.sh` | 1 | Required/optional systemd services, failed units |
| `check-ipmi.sh` | 1 | PSU status, CPU temps, ECC memory errors |
| `check-nfs.sh` | 1 | NFS service and export status (skips if not installed) |
| `check-snapraid.sh` | 2 | SnapRAID sync errors, scrub recency (skips if not installed) |

Each script:
- Sources `/usr/local/lib/monitoring/lib/alert.sh` for shared alert dispatch
- Writes `.prom` metrics to the textfile collector directory
- Uses file-based deduplication to avoid alert floods
- Exits cleanly if its target service isn't installed

---

## Adding a New Machine

1. Add `monitoring-base` and `monitoring-checks` roles to the machine's playbook:

```yaml
- name: Machine monitoring setup
  hosts: new-machine
  become: yes
  tags: [monitoring]
  roles:
    - monitoring-base
    - monitoring-checks
```

2. Override defaults in the machine's inventory or group vars as needed:

```yaml
# Example: disable IPMI on machines without a BMC
ipmi_exporter_enabled: false

# Example: adjust load thresholds for a 4-core machine
monitoring_load_warn: 6
monitoring_load_crit: 8

# Example: add machine-specific required services
monitoring_required_services:
  - smartd
  - prometheus-node-exporter
  - kubelet
```

3. Run the playbook: `ansible-playbook -i inventory/machine.yml playbooks/setup-machine.yml --tags monitoring`

---

## Wiring Up Alerting

By default, all alerts go to syslog (`journalctl -t monitoring`). To enable webhook delivery:

### Option A: Generic Webhook

Set `monitoring_alert_webhook_url` in your inventory or group vars:

```yaml
monitoring_alert_webhook_url: "https://your-endpoint.example.com/alerts"
```

The payload is JSON:
```json
{
  "level": "critical",
  "check": "check-smart",
  "alert_id": "health_sda",
  "host": "r730xd",
  "message": "SMART health check FAILED for /dev/sda",
  "timestamp": "2026-03-28T14:30:00-04:00"
}
```

### Option B: Ntfy

Point the webhook URL at your Ntfy topic:

```yaml
monitoring_alert_webhook_url: "https://ntfy.example.com/homelab-alerts"
```

Note: Ntfy expects different payload format. You may need to customize `alert.sh` to use Ntfy's API (simple curl with `-d "message"` and `-H "Title: ..."` headers) instead of the generic JSON POST. A Ntfy-specific dispatch function would look like:

```bash
curl -sf -H "Title: [${level^^}] ${check}" \
     -H "Priority: $([ "$level" = "critical" ] && echo "urgent" || echo "default")" \
     -H "Tags: ${level}" \
     -d "$message" \
     "$ALERT_WEBHOOK_URL" >/dev/null 2>&1
```

### Option C: Alertmanager Webhook Receiver

When Prometheus + Alertmanager is running (see next section), you can point `alert.sh` at Alertmanager's webhook receiver for unified alert routing. However, at that point the cron-based alerts become redundant — Alertmanager rules replace them.

---

## Migrating to Prometheus + Alertmanager

### Prerequisites

- A machine or K8s namespace to run Prometheus and Alertmanager
- Network access from Prometheus to each host's exporter ports (`:9100`, `:9290`)

### Step 1: Prometheus Scrape Configuration

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "rules/*.yml"

scrape_configs:
  - job_name: "node"
    static_configs:
      - targets:
          - "<r730xd_ip>:9100"   # r730xd
          # Add more hosts as they come online
        labels:
          env: "homelab"

  - job_name: "ipmi"
    static_configs:
      - targets:
          - "<r730xd_ip>:9290"   # r730xd
        labels:
          env: "homelab"
```

### Step 2: Alert Rules

These Prometheus alerting rules replicate the cron check logic:

```yaml
# rules/homelab.yml
groups:
  - name: storage
    rules:
      - alert: DiskSpaceWarning
        expr: (1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk {{ $labels.mountpoint }} is {{ $value | printf \"%.0f\" }}% full on {{ $labels.instance }}"

      - alert: DiskSpaceCritical
        expr: (1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 > 95
        for: 2m
        labels:
          severity: critical

      - alert: SmartUnhealthy
        expr: monitoring_smart_healthy == 0
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "SMART health check failed for {{ $labels.device }} on {{ $labels.instance }}"

      - alert: DriveTemperatureHigh
        expr: monitoring_smart_temperature_celsius > 55
        for: 5m
        labels:
          severity: critical

      - alert: ReallocatedSectors
        expr: monitoring_smart_reallocated_sectors > 5
        for: 0m
        labels:
          severity: warning

  - name: hardware
    rules:
      - alert: PSUFailure
        expr: monitoring_ipmi_psu_failed > 0
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "Power supply failure detected on {{ $labels.instance }}"

      - alert: CPUTemperatureHigh
        expr: monitoring_ipmi_temperature_celsius > 85
        for: 5m
        labels:
          severity: critical

      - alert: ECCMemoryErrors
        expr: monitoring_ipmi_memory_errors_sel > 0
        for: 0m
        labels:
          severity: warning

  - name: services
    rules:
      - alert: ServiceDown
        expr: monitoring_service_up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.service }} is down on {{ $labels.instance }}"

      - alert: SystemdFailedUnits
        expr: monitoring_systemd_failed_units > 0
        for: 5m
        labels:
          severity: warning

  - name: nfs
    rules:
      - alert: NFSDown
        expr: monitoring_nfs_service_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "NFS server is down on {{ $labels.instance }} — K8s PVCs affected"

  - name: snapraid
    rules:
      - alert: SnapRAIDErrors
        expr: monitoring_snapraid_errors > 0
        for: 0m
        labels:
          severity: critical

      - alert: SnapRAIDScrubOverdue
        expr: monitoring_snapraid_last_scrub_days > 7
        for: 0m
        labels:
          severity: warning
```

### Step 3: Textfile Collector Metrics

The `monitoring_*` metrics in the alert rules above come from the cron check scripts via the textfile collector. **No changes needed** — Prometheus scrapes node\_exporter which automatically picks up the `.prom` files.

This means you get both the standard node\_exporter metrics *and* the custom health check metrics from a single scrape target.

### Step 4: What to Retire

Once Alertmanager rules cover the same signals:

| Component | Keep or retire? |
|-----------|----------------|
| node\_exporter | **Keep** — Prometheus needs it |
| ipmi\_exporter | **Keep** — Prometheus needs it |
| smartd | **Keep** — drives still need self-tests |
| Cron check scripts | **Optional** — keep as belt-and-suspenders, or remove. The textfile metrics they write are still useful even if alerts move to Alertmanager |
| `alert.sh` webhook dispatch | **Retire** — Alertmanager handles routing |

---

## Migrating to Grafana Dashboards

Once Prometheus is running, add Grafana and import these dashboards:

| Dashboard | Grafana ID | Covers |
|-----------|-----------|--------|
| Node Exporter Full | 1860 | CPU, RAM, disk I/O, network, filesystem |
| IPMI Exporter | Community | PSU, fans, voltages, temperatures |
| Custom: Storage Health | — | SnapRAID status, SMART metrics, MergerFS pool usage |

### Key Prometheus Queries by Signal

| Signal | PromQL |
|--------|--------|
| Disk usage | `(1 - node_filesystem_avail_bytes/node_filesystem_size_bytes) * 100` |
| CPU temperature | `monitoring_ipmi_temperature_celsius{sensor=~".*CPU.*"}` |
| Drive temperature | `monitoring_smart_temperature_celsius` |
| SMART health | `monitoring_smart_healthy` |
| Reallocated sectors | `monitoring_smart_reallocated_sectors` |
| PSU status | `monitoring_ipmi_psu_failed` |
| NFS up | `monitoring_nfs_service_up` |
| SnapRAID errors | `monitoring_snapraid_errors` |
| System load | `node_load5` |
| Network throughput | `rate(node_network_receive_bytes_total[5m])` |

---

## Migrating to Grafana Alloy

[Grafana Alloy](https://grafana.com/oss/alloy/) is Grafana's OpenTelemetry Collector distribution. It scrapes Prometheus endpoints natively, so everything in the current setup works with it unchanged. Alloy can replace a standalone Prometheus server — it scrapes, processes, and pushes metrics to a backend (Mimir, Prometheus remote write, Grafana Cloud, or any OTLP endpoint).

### Deployment Models

**Option A: Alloy as central scraper** (recommended to start)

Run Alloy on one machine (or in K8s). It scrapes all hosts' exporters remotely. Hosts keep their current exporters with no changes.

**Option B: Alloy on each host** (agent mode)

Replaces node\_exporter with Alloy's built-in `prometheus.exporter.unix`. Each Alloy instance pushes its own metrics to a central backend. More infrastructure to deploy, but fewer services per host.

IPMI exporter has no Alloy-native equivalent — keep the standalone exporter in either model.

### Alloy Configuration (Option A — Central Scraper)

```alloy
// --- Scrape all hosts ---

prometheus.scrape "node" {
  targets = [
    {"__address__" = "<r730xd_ip>:9100", "instance" = "r730xd"},
    // Add more hosts as they come online
  ]
  forward_to = [prometheus.remote_write.default.receiver]
  scrape_interval = "15s"
}

prometheus.scrape "ipmi" {
  targets = [
    {"__address__" = "<r730xd_ip>:9290", "instance" = "r730xd"},
  ]
  forward_to = [prometheus.remote_write.default.receiver]
  scrape_interval = "30s"
}

// --- Push to backend ---

prometheus.remote_write "default" {
  endpoint {
    url = "http://mimir:9009/api/v1/push"
  }
}
```

### Alloy Configuration (Option B — Per-Host Agent)

```alloy
// Built-in system metrics (replaces node_exporter)
prometheus.exporter.unix "default" {}

prometheus.scrape "self" {
  targets = prometheus.exporter.unix.default.targets
  forward_to = [prometheus.remote_write.default.receiver]
  scrape_interval = "15s"
}

// Still need to scrape ipmi_exporter (no Alloy-native equivalent)
prometheus.scrape "ipmi" {
  targets = [{"__address__" = "localhost:9290"}]
  forward_to = [prometheus.remote_write.default.receiver]
  scrape_interval = "30s"
}

// Textfile collector metrics (reads the .prom files from cron checks)
local.file_match "textfile" {
  path_targets = [{"__path__" = "/var/lib/prometheus/node-exporter/*.prom"}]
}

// Ship logs from journal (includes monitoring syslog entries)
loki.source.journal "default" {
  forward_to = [loki.write.default.receiver]
  labels = {job = "journal"}
}

loki.write "default" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}

prometheus.remote_write "default" {
  endpoint {
    url = "http://mimir:9009/api/v1/push"
  }
}
```

Note: In agent mode, the `prometheus.exporter.unix` component does **not** automatically read textfile collector `.prom` files the way node\_exporter does. You would either keep node\_exporter alongside Alloy for textfile collection, or switch the cron check scripts to push metrics via Alloy's OTLP receiver instead.

### Alloy + Alerting

Alloy itself doesn't evaluate alert rules — that's handled by the backend:

- **With Mimir:** Use Mimir's ruler component with the same Prometheus alert rules from the "Migrating to Prometheus + Alertmanager" section above
- **With Grafana Cloud or self-hosted Grafana:** Use Grafana Alerting (unified alerting) to define alert rules against the metrics in your data source
- **With standalone Prometheus:** Alloy pushes via remote write, Prometheus evaluates rules and routes to Alertmanager

In all cases, the cron-based `alert.sh` webhook alerts continue working independently as a fallback until you're confident in the centralized alerting pipeline.

### What Changes per Deployment Model

| Component | Option A (central) | Option B (per-host agent) |
|-----------|-------------------|--------------------------|
| node\_exporter | **Keep** on each host | **Replace** with `prometheus.exporter.unix` |
| ipmi\_exporter | **Keep** on each host | **Keep** — no Alloy equivalent |
| Textfile `.prom` files | **Keep** — node\_exporter reads them | **Keep node\_exporter** for textfile, or rework scripts to push OTLP |
| smartd | **Keep** | **Keep** |
| Cron checks | **Keep** — textfile metrics flow through node\_exporter | **Keep** — but alert dispatch can migrate to Grafana Alerting |
| Alloy install | Central machine or K8s only | Every monitored host |

### Recommended Path for This Homelab

Start with **Option A** — a single Alloy instance scraping all hosts. This avoids deploying Alloy to every machine and keeps the per-host stack simple (exporters + cron checks). When K8s is running, deploy Alloy as a K8s workload alongside Mimir and Grafana. The exporters and textfile metrics on each host continue working without changes.

---

## Migrating to a Different Stack

If you switch from Prometheus to Zabbix, Checkmk, Datadog, or another monitoring system:

### What's Reusable

The check scripts at `/usr/local/lib/monitoring/checks/` are standalone bash scripts. They:
- Exit 0 on success, non-zero on failure
- Write human-readable output to stdout/stderr
- Can be wrapped by any agent-based monitoring system as custom checks

For example, with Zabbix agent:
```
UserParameter=smart.health,/usr/local/lib/monitoring/checks/check-smart.sh
```

### What to Replace

| Component | Replacement |
|-----------|-------------|
| `alert.sh` dispatcher | New stack's native alerting |
| Cron scheduling | New stack's agent scheduling |
| node\_exporter | Stack's own system agent (e.g., Zabbix agent, Datadog agent) |
| ipmi\_exporter | Stack's own IPMI integration |
| Textfile collector `.prom` files | Not needed — remove or keep for dual-stack |

### What to Keep Regardless

- **smartd** — drive self-tests are OS-level, independent of monitoring stack
- **ipmitool** — useful for manual diagnostics regardless of monitoring
- **edac-utils** — OS-level ECC reporting
