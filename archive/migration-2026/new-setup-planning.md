# New Setup Planning

Last updated: 2026-04-17

## Status

Everything in the role-assignment table below is now either **live** or **pending a known next step**. This document is kept as a reference for the planning rationale behind each role; for day-to-day "what's running where", see `../../docs/hardware.md`.

## Target Architecture

```
                         Internet
                            |
                            v
                 +--------------------+
                 |    Hetzner VPS     |
                 |  Caddy + NetBird   |
                 +--------------------+
                            |
                 (dedicated WG tunnel to R730xd; see ADR-019)
                            |
                            v
                 +--------------------+
                 |   R730xd (home)    |
                 |  iptables DNAT →   |
                 |  K8s NodePort      |
                 +--------------------+
                            |
     +----------+-----------+-----------+-----------+
     |          |           |           |           |
     v          v           v           v           v
+----------+ +----------+ +----------+ +----------+ +----------+
| Quanta   | | NUC      | | Optiplex | | Inspiron | | Tower PC |
| K8s Wkr  | | K8s Wkr  | | K8s Wkr  | | K8s CP   | | K8s Wkr  |
| 16C/64GB | | 14C/64GB | | 4C/32GB  | | 2C/8GB   | | pending  |
+----------+ +----------+ +----------+ +----------+ +----------+

+-------------------+         +-------------------+
| R730xd Storage    |         | GPU Inference     |
| MergerFS + ZFS    |         | Host (new build)  |
| Obs + Foundation  |         | Standalone        |
+-------------------+         +-------------------+
```

**NetBird** is used only as an operator management plane. Service traffic from the VPS into home goes through the dedicated WireGuard `/30` tunnel that terminates on R730xd.

## Decided Role Assignments

### Dell PowerEdge R730xd → Storage + Observability + Foundation Stores (Standalone)

- **Role:** Dedicated storage server + observability + foundation data stores. Terminator for the VPS → home ingress WG tunnel (ADR-019). Runs Docker Compose for all non-K8s workloads on this box.
- **Why:** Up to 12× 3.5" front hot-swap bays + 2× 2.5" rear + 4-port NIC + iDRAC. Purpose-built for storage; the RAM and CPU headroom make it a good home for Postgres / Redis / MinIO / LGTM stack.
- **Replaces:** the old tower-pc NFS role.
- **Storage layout:**
  - MergerFS pool (`/mnt/pool`): 5×3TB data + 2×4TB SnapRAID parity. 15 TB usable. Bulk / cold storage; backs K8s `nfs-mergerfs` StorageClass and MinIO Bulk.
  - ZFS `tank` (`/mnt/zfs`): 3×2TB raidz1 (migrated from old tower-pc). ~3.6 TB usable. Latency-sensitive services; backs K8s `iscsi-zfs` StorageClass via democratic-csi.
  - 3TB drive with pre-existing data: mounted directly into the MergerFS pool ([ADR-007](../../docs/decisions/007-3tb-data-drive-direct-to-pool.md)).
- **Storage software:** MergerFS + SnapRAID (mismatched drives, no license cost); ZFS for hot-write workloads (splits laid out in [ADR-012](../../docs/decisions/012-hot-services-on-zfs-minio-split.md)).
- **Boot cache:** bcache SSD for MergerFS deferred — not blocking.
- **Observability stack:** Prometheus, Alertmanager, Loki, Tempo, Grafana, Alloy, cAdvisor, blackbox-exporter (Docker Compose on ZFS). Deployed via `ansible/playbooks/deploy-observability.yml`.
- **Foundation stores:** Postgres 16, Redis 7, MinIO Obs (hot/ZFS), MinIO Bulk (cold/MergerFS). Deployed via `ansible/playbooks/deploy-foundation-stores.yml`.

### Quanta QSSC-2ML → Primary K8s Worker

- **Role:** Main K8s compute — 16C/32T, 64 GB RAM, fully dedicated to the cluster.
- **Boot:** Local SSD ([ADR-013](../../docs/decisions/013-local-disk-over-pxe-boot.md), superseded PXE-boot / NFS-root plans).
- **Network:** 4-port NIC via PCIe riser installed. Direct-to-R730 dedicated storage link is an optional optimization revisited alongside the storage VLAN (see `../../docs/exploration/network-vlans.md`).
- **Status:** **Live K8s worker.**

### Intel NUC12SNKi72 → K8s Worker

- **Role:** K8s worker (14C/20T i7-12700H, 64 GB RAM). Second-strongest worker.
- **Origin:** Grandfather's NUC; Intel ARC GPU is dead but display works via USB-C (headless is fine).
- **Boot:** Local NVMe.
- **Status:** **Live K8s worker.**

### Dell Optiplex 9020 → K8s Worker

- **Role:** K8s worker (i7-4790 4C/8T, 32 GB RAM).
- **Previous role:** Standalone "deb-web" — web hosting + Palworld + self-hosted Actions runner. All three retired:
  - Web services migrated onto K8s via Flux (landing-page, caz-portfolio, resume-site).
  - Palworld decommissioned indefinitely ([ADR-022](../../docs/decisions/022-palworld-decommissioned.md)).
  - Self-hosted runner replaced by in-cluster ARC v2 ([ADR-017](../../docs/decisions/017-arc-v2-github-runners.md)).
- **Boot:** Local SSD.
- **Status:** **Live K8s worker.**

### Dell Inspiron 15 → K8s Control Plane

- **Role:** Single control plane node (2C/4T i3-7100U, 8 GB). Adequate for this cluster size ([ADR-016](../../docs/decisions/016-single-control-plane.md)).
- **Boot:** Local SSD.
- **Status:** **Live control plane.**

### Tower PC → K8s Worker (Pending Join)

- **Role:** Plain K8s worker. No router role, no GPU role — both superseded by [ADR-021](../../docs/decisions/021-off-the-shelf-router-tower-pc-as-worker.md).
- **Why no GPU:** PSU is insufficient for the planned 3-GPU fleet. Rather than upgrade the PSU, the GPU workload moves to a separate new-build host (below).
- **Specs:** i7-4790 (4C/8T), 24 GB RAM. Modest contribution to the cluster, but it's already owned hardware.
- **Status:** Not yet in `ansible/inventory/lab-nodes.yml` — will be added at kubeadm-join time.

### GPU Inference Host → Standalone (Being Built)

- **Role:** Dedicated inference host (Ollama / vLLM / text-generation-inference TBD). Consumed over the LAN by cluster workloads and developer tools.
- **Why standalone:** Keeps inference reboots / driver updates independent of cluster drains. Also avoids pulling NVIDIA device-plugin machinery into the cluster for a single host.
- **GPUs:** 1080 Ti (11 GB), 1060 (3 GB), 1050 Ti (4 GB). GTX 760 (2 GB) probably not worth a slot.
- **Status:** Hardware build in progress. Specs / hostname / IP / ADR pending hardware arrival. Tracked in `../../docs/hardware.md` as "Future / pending".

### Mini PC (AMD C60) → Jumpbox / Command Center

- **Role:** Dedicated jumpbox — SSH gateway, `kubectl` + `helm`, Claude Code, stats display.
- **Storage:** SSD (salvaged from Optiplex or Inspiron) to replace the slow 3TB HDD.
- **Why:** C60 is too slow for routing or anything heavy, but fine for terminal / SSH work.
- **Status:** Build script + Sway configs ready; imaging pending.

### proxy-vps (Hetzner) → Stays As-Is

- Caddy reverse proxy + NetBird VPN gateway. Terminates wildcard `*.bearflinn.com` TLS. Routes to K8s via the dedicated WG tunnel to R730xd (ADR-019).
- Role unchanged.

## Boot & Storage Strategy

**K8s nodes boot from local disk** ([ADR-013](../../docs/decisions/013-local-disk-over-pxe-boot.md)). The previously-planned PXE / NFS-root setup was dropped — local installs are simpler, faster to bring up, and have fewer moving parts.

**Stateful workloads live on R730xd**, not in the K8s nodes. The cluster provisions PVCs via democratic-csi:

- `iscsi-zfs` (default) — zvols on the ZFS `tank` pool (latency-sensitive apps).
- `nfs-mergerfs` — NFS from the MergerFS pool (bulk).

**SSD redistribution (historical):**

| SSD | Source | Destination | Purpose |
|-----|--------|-------------|---------|
| 256 GB | Inspiron (old plan) | Jumpbox | OS + Claude Code I/O |
| 512 GB | Optiplex (old plan) | ~~Tower PC LLM storage~~ | Revisit for the GPU host when it lands |
| 128 GB NVMe | Tower PC (old plan) | ~~R730 bcache~~ | bcache deferred; NVMe can stay with Tower PC |

Actual moves are bookkeeping — what matters is that all machines now boot from local disk and K8s storage is backed by R730xd.

## Network Equipment

### SR2024 Switch

- 24-port managed GbE backbone for the closet.
- Live today as a **flat L2** backbone. VLAN trunks + per-VLAN tagging deferred until the off-the-shelf router ([ADR-021](../../docs/decisions/021-off-the-shelf-router-tower-pc-as-worker.md)) is in place. See `../../docs/exploration/network-vlans.md` for the VLAN design.

### Aerohive APs (2× AP130, 1× AP230, 1× AP630)

- AP630 primary (4×4:4 MU-MIMO, 802.11ac Wave 2). Restored to stock HiveOS 2026-04-03 ([ADR-011](../../docs/decisions/011-ap630-restored-to-stock-wifi-ap.md)).
- AP230 secondary (3×3:3 MIMO). Starting AP per [ADR-009](../../docs/decisions/009-start-with-ap230-only.md).
- AP130s for coverage extension.
- All 4 run HiveOS standalone (no cloud controller).
- Physical mounting still pending.

## Network Topology

Current state is a flat SR2024 network with the Xfinity gateway upstream. The target architecture (VLANs, custom router, router-side DNS) lives in `../../docs/exploration/network-vlans.md` and is gated on the off-the-shelf router purchase.

## K8s Cluster Summary (Live)

| Resource | Total |
|----------|-------|
| Control plane nodes | 1 (Inspiron) |
| Worker nodes | 3 live (Quanta, NUC, Optiplex) + 1 pending (Tower PC) |
| CPU cores (workers, live) | 34C/60T (16+14+4, thread counts 32+20+8) |
| RAM (workers, live) | 160 GB (64 + 64 + 32) |
| RAM (CP) | 8 GB |
| K8s version | v1.33.10 |

Tower PC adds +4C/8T and +24 GB RAM once joined.

## Open Decisions

- [x] ~~K8s vs alternatives~~ — **keeping K8s.**
- [x] ~~Quanta / NUC / Optiplex / Inspiron roles~~ — **all decided; all live.**
- [x] ~~R730 role~~ — **storage + observability + foundation stores.**
- [x] ~~Tower PC role~~ — **plain K8s worker ([ADR-021](../../docs/decisions/021-off-the-shelf-router-tower-pc-as-worker.md)).**
- [x] ~~Router sourcing~~ — **off-the-shelf, deferred purchase (ADR-021).**
- [x] ~~R730 storage software~~ — **MergerFS + SnapRAID for bulk; ZFS `tank` for hot services; democratic-csi for K8s.**
- [x] ~~R730 drive layout~~ — **2×4TB parity (bays 0+3), 5×3TB data (bays 1+2+4+5+8), 3×2TB ZFS (bays 9+10+11). See `ansible/inventory/r730xd.yml`.**
- [x] ~~3TB data handling~~ — **direct mount into MergerFS pool ([ADR-007](../../docs/decisions/007-3tb-data-drive-direct-to-pool.md)).**
- [x] ~~Drive migration from tower-pc~~ — **done 2026-04-03 (ZFS pool `tank`).**
- [x] ~~Network topology choice~~ — **flat now, VLANs post-router. See `../../docs/exploration/network-vlans.md`.**
- [x] ~~Tower PC PSU audit~~ — **confirmed insufficient for 3 GPUs; GPU workload moves to separate host.**
- [ ] **GPU inference host** — hardware build in progress; needs its own ADR + inventory entry when it lands.
- [ ] **Router model selection** — UniFi / OPNsense appliance / similar. Decide when ready to buy.
- [ ] **Power assessment** — revisit once GPU host is built (sustained multi-GPU draw could stress the closet circuits).
- [ ] **UPS strategy** — APC RS 1500 batteries dead. Replace + wire NUT before relying on it. R730 / Quanta need pure sine — out of scope for this UPS anyway.
- [ ] **Quanta sine-wave tolerance** — deferred, not blocking (no live UPS).
