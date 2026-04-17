# Migration Plan

> **IP addresses:** Authoritative values are in `ansible/group_vars/all/network.yml`.

Last updated: 2026-04-17

## Status at a Glance (2026-04-17)

The bulk of the migration is done. The new K8s cluster is live (Inspiron CP + Quanta/NUC/Optiplex workers on v1.33.10), Flux is green, all three migrated apps run on GitOps, the observability + foundation stacks are deployed on R730xd, and the staging VM has been torn down. All lab hardware is physically in the closet on the SR2024.

What's left is a small closeout list (see **Remaining Work** at the top of Phase-level sections): purchase an off-the-shelf router ([ADR-021](../decisions/021-off-the-shelf-router-tower-pc-as-worker.md)) and configure VLANs once it arrives, join the Tower PC to the cluster as a plain worker, build out the new GPU inference host, mount remaining APs, and replace UPS batteries.

Hardware/plan deltas since 2026-04-05 (reflected below):

- **MSI laptop** — given away; out of the inventory entirely. Replaced personally by a non-infra dev laptop.
- **Optiplex** — fully committed as a K8s worker; no longer "deb-web".
- **Tower PC** — no longer a router / GPU host; will join as a plain K8s worker (ADR-021). Separate new machine being built for GPU inference.
- **Custom router project** — deferred; buying off-the-shelf instead (ADR-021).
- **Palworld** — decommissioned indefinitely ([ADR-022](../decisions/022-palworld-decommissioned.md)).

## Guiding Principles

- **Current cluster stays functional** until new infrastructure is ready to take over
- **Data safety first** — ~~back up the 3TB drive before touching any storage~~ (resolved — [ADR-007](../decisions/007-3tb-data-drive-direct-to-pool.md))
- **Network before compute** — machines need connectivity before they can be configured
- **One role at a time** — don't drain a machine from K8s until its replacement is confirmed working

---

## Migration Strategy

**Staging approach (executed):** Critical workloads ran on a staging VM on the R730 during the cluster rebuild. Decommissioned 2026-04-09 after Phase 7b moved landing-page, caz-portfolio, and resume-site onto the new K8s cluster ([ADR-002 — Superseded](../decisions/002-r730-staging-vm-for-migration.md)).

**Anchor machine (executed):** R730 came online first with storage, staging VM, foundation stores, and observability. All subsequent work assumed R730 as the central fixed point.

---

## Phase 0: Assessment & Prep (No Downtime)

Do all of this before touching the physical setup. Can be done in parallel.

### 0A: Hardware Assessment

- [x] ~~Test POST on R730xd~~ — **confirmed. BIOS 2.3.4, iDRAC accessible.**
- [x] ~~Identify R730xd CPU~~ — **Intel Xeon E5-2630 v3 (8C/16T @ 2.4 GHz, 85W)**
- [x] ~~Check R730xd drive bay config~~ — **12× 3.5" front + 2× 2.5" rear confirmed**
- [x] ~~Remove 3TB drive from mini PC~~ — **physically removed 2026-03-26, data preserved via [ADR-007](../decisions/007-3tb-data-drive-direct-to-pool.md)**
- [x] ~~Test POST on Quanta~~ — **confirmed. AMI BIOS, boots to EFI shell (no drives).**
- [x] ~~Identify Quanta CPUs~~ — **2× Intel Xeon E5-2670 (Sandy Bridge-EP), 8C/16T each = 16C/32T total @ 2.6 GHz**
- [x] ~~Check Quanta drive bays~~ — **6× SATA, no hot-swap bays, internal mount only, currently empty**
- [x] ~~Configure Quanta BMC/IPMI~~ — **static IP set, dedicated NIC port**
- [ ] **Verify Quanta sine wave tolerance** — will it run on the APC UPS or does it need pure sine? **Deferred — irrelevant until UPS batteries are replaced.**
- [x] ~~Audit Tower PC PSU~~ — **determined insufficient for the planned 3-GPU inference fleet. Tower PC repurposed as plain K8s worker; GPU inference moves to a separate new-build host. See [ADR-021](../decisions/021-off-the-shelf-router-tower-pc-as-worker.md).**
- [x] ~~Test SR2024 switch~~ — **fully operational. VLANs, LACP, PoE all confirmed. Now the lab backbone in the closet.**
- [x] ~~Check Aerohive AP + switch firmware~~ — **confirmed standalone capable, no cloud dependency (per previous owner)**
- [ ] **Check UPS** — APC RJ45-to-USB data cable still needed for NUT monitoring. **Deferred — batteries are dead; not blocking migration.**

### 0B: Data Safety

- [x] ~~Back up critical data before migration:~~
  - ~~3TB drive (removed from mini PC 2026-03-26)~~ — **mounted directly into R730xd MergerFS pool (bay 8). Data preserved in-place, no separate backup needed. See [ADR-007](../decisions/007-3tb-data-drive-direct-to-pool.md).**
  - [x] ~~Palworld server data (Optiplex / old deb-web)~~ — **save data + config backed up 2026-04-03 to `~/Backups/deb-web/` (52MB). Service decommissioned indefinitely, see [ADR-022](../decisions/022-palworld-decommissioned.md).**
  - [x] ~~Residuum files (Optiplex / old deb-web)~~ — **backed up 2026-04-03 to `~/Backups/deb-web/` (30MB). Residuum's live ingestion path now runs in-cluster as the `feedback-ingest` Helm release; agent-residuum.com redirect preserved on proxy-vps.**
  - Everything else is stale or expendable (tower-pc ZFS pool ~9MB, duplicate apps on the old Optiplex deb-web host)

### 0C: Inventory Current Services

Document everything that's running so nothing gets lost in the migration:

- [x] ~~K8s workloads~~ — **inventoried + migrated. New cluster runs apps via Flux (landing-page, caz-portfolio, resume-site, feedback-ingest) plus infra (ingress-nginx, cert-manager, registry, ARC runners, Argo Workflows, democratic-csi).**
- [x] ~~Old Optiplex / deb-web services~~ — **decommissioned. Duplicate Docker Compose apps, old Prometheus/Grafana, Caddy, cloudflared, agent-docs-sync all torn down when the host was rebuilt as a K8s worker. Palworld saved + decommissioned ([ADR-022](../decisions/022-palworld-decommissioned.md)). Self-hosted GitHub Actions runner replaced by in-cluster ARC v2 ([ADR-017](../decisions/017-arc-v2-github-runners.md)).**
- [x] ~~Tower-pc services~~ — **NFS export and ZFS pool data migrated in Phase 4A. 3×2TB drives moved into R730xd bays 9/10/11 (ZFS raidz1 pool `tank`). No data loss.**
- [x] ~~MSI laptop workloads~~ — **Nothing custom. Drained 2026-03-26, removed from cluster 2026-04-03. Hardware given away — no longer in the inventory at all.**
- [x] ~~DNS/networking dependencies~~ — **flattened onto current topology: NFS export scoped to lab subnet via the `r730xd-nfs-server` role; VPS → cluster via dedicated WG tunnel ([ADR-019](../decisions/019-ingress-and-tls-termination.md)), not NetBird subnet routes.**
- [x] ~~Ansible vault~~ — **.vault_pass exists, backed up outside repo; pre-commit hook validates vault files (commit `ec0fefc`).**
- [x] ~~cloudflared on old deb-web~~ — **removed during Optiplex rebuild.**
- [x] ~~agent-docs-sync on old deb-web~~ — **removed during Optiplex rebuild.**

### 0D: Gather Supplies

- [x] ~~Ethernet cable~~ — **~300ft cat6 on hand**
- [x] ~~PoE for APs~~ — **switch has 12 PoE ports, no injectors needed**
- [ ] APC RJ45-to-USB data cable (940-0127 or compatible) — **deferred, UPS batteries dead anyway**
- [ ] Replacement UPS batteries — **needed before UPS can be used**
- [x] ~~Power strips~~ — **on hand**
- [x] ~~Closet power~~ — **dedicated 20A circuit**
- [x] ~~RJ45-to-USB console cable for Aerohive AP/switch configuration~~ — **received, used to factory reset all 3 APs (2026-03-27)**
- [x] ~~PCIe riser for Quanta~~ — **received, 4-port NIC installed (2026-03-27)**

---

## Phase 1: Physical Infrastructure (Planned Downtime)

This is the big move. The current cluster goes down, everything gets relocated.

### 1A: Prepare the Closet

- [x] ~~Install shelving~~ — **done**
- [x] ~~Run power to closet~~ — **2× 15A circuits available. Note: closet has 12 AWG wire and 20A outlet but is on a 15A breaker. Load balanced across both circuits.**
- [x] ~~Plan physical layout~~ — **R730 + Quanta on lower shelves, SR2024 accessible, lighter machines higher**

### 1B: Run Cable

- Non-lab network (bedroom, garage) staying on existing switch chain for now. See [ADR-008](../decisions/008-keep-existing-switch-chain-for-home.md).
- [x] ~~Closet ↔ AP230 location~~ — **cable run in place; AP230 mounting still pending (see Phase 4B).**
- [x] ~~Closet ↔ Xfinity gateway (living room)~~ — **uplink in place; Xfinity gateway is still doing the routing (flat L2 in the lab) until the off-the-shelf router from [ADR-021](../decisions/021-off-the-shelf-router-tower-pc-as-worker.md) arrives.**

### 1C: Set Up Switch & Network

The SR2024 is the lab backbone. VLANs are **deferred until the off-the-shelf router arrives** ([ADR-021](../decisions/021-off-the-shelf-router-tower-pc-as-worker.md)) — configuring VLANs on top of the Xfinity gateway's routing buys us very little, and the purchased router will handle inter-VLAN routing much more cleanly than any DIY option.

- [x] ~~Initial closet networking~~ — **SR2024 installed in the closet as the lab backbone (2026-04). All lab machines hang off it.**
- [x] ~~Mount SR2024 in closet~~ — **done.**
- [x] ~~Connect Xfinity uplink to switch~~ — **done; Xfinity gateway still routes (flat L2 in the lab).**
- [ ] Configure VLANs on SR2024 — **deferred until off-the-shelf router is in place (ADR-021). Target design:**
  - VLAN 1 (default/untagged): Home network — DHCP from new router, bedroom, garage, APs
  - VLAN 10 (tagged): Lab — all lab machines
  - VLAN 20 (tagged, optional): Storage — R730 ↔ K8s nodes dedicated iSCSI/NFS traffic
- [x] ~~Assign switch ports~~ — **flat assignments to date; VLAN assignments pending per above.**
- [x] ~~Test connectivity: machine on switch can reach internet via Xfinity gateway~~ — **continuously verified; cluster is live.**

### 1D: Move Existing Machines

- [x] ~~Drain MSI laptop from K8s~~ — **done 2026-03-26. Workloads drained; node cordoned, then force-deleted 2026-04-03. Hardware subsequently given away — no longer in the inventory.**
- [x] ~~Drain Tower PC from old K8s~~ — **done 2026-04-03. Force-deleted from the old cluster. Will rejoin the new cluster as a plain worker ([ADR-021](../decisions/021-off-the-shelf-router-tower-pc-as-worker.md)).**
- [x] ~~Shut down the old cluster~~ — **done 2026-04-03. Old kubelet/containerd stopped. Staging VM served public traffic during the new cluster's standup; new cluster took over by Phase 7b.**
- [x] ~~Physically move Inspiron, Optiplex to closet~~ — **done. Both are live K8s nodes on the SR2024.**
- [x] ~~Physically move Tower PC to closet~~ — **done (in or near the closet). Not yet joined to the new cluster.**
- [x] ~~Connect all moved machines to SR2024~~ — **done.**
- [x] ~~Boot Inspiron (control plane) first, verify K8s API comes up~~ — **done. New control plane running on v1.33.10.**
- [x] ~~Verify Optiplex connectivity~~ — **done. Optiplex is a live worker.**

### 1E: UPS Setup

~~Skipped — APC RS 1500 batteries are dead and need replacement. Proceeding without UPS for now. See [ADR-006](../decisions/006-proceed-without-ups.md).~~

- [ ] Replace UPS batteries (deferred — not blocking migration)
- [ ] Revisit UPS + NUT setup after battery replacement

---

## Phase 2: New Machines Online

### 2A: R730 — Storage Server + PXE Server

- [x] ~~Install boot drive~~ — **Samsung SSD 850 EVO 250GB in rear bay 12 (non-RAID mode)**
- [x] ~~Install data drives~~ — **7 drives installed: 2×4TB (parity, bays 0+3) + 5×3TB (data, bays 1+2+4+5+8). Bay 8 contains the original 3TB with existing data, mounted directly into pool.**
- [x] ~~Install OS~~ — **Debian 13.4 (Trixie) installed 2026-03-26 via preseeded USB (fully scripted: `scripts/build-r730xd-iso.sh`). UEFI boot, static IP `<r730xd_ip>`, SSH key auth, baseline playbook applied (`ansible/playbooks/setup-r730xd.yml`).**
- [x] ~~Configure storage~~ — **done 2026-03-31. MergerFS pool at `/mnt/pool` (5×3TB data), SnapRAID parity (2×4TB). Deployed via `ansible/playbooks/r730xd-storage.yml`.**
  - [ ] bcache SSD for read acceleration (deferred — not blocking)
- [x] ~~Set up NFS exports for K8s PVCs~~ — **done 2026-03-31. `/mnt/pool` exported to `<lab_subnet>` via `r730xd-nfs-server` role.**
- [x] ~~Set up ZFS pool on 3×2TB drives (migrated from tower-pc) for latency-sensitive workloads~~ — **done 2026-04-03. ZFS raidz1 pool `tank` (3×2TB, bays 9+10+11) mounted at `/mnt/zfs`. ~3.6TB usable. lz4 compression, 4GB ARC max. Monitoring: `check-zfs.sh` (tier 1, every 5 min), Prometheus alert rules (degraded/capacity/errors/scrub). See [ADR-004](../decisions/004-zfs-iscsi-for-k8s-storage.md). Deployed via `ansible/playbooks/r730xd-zfs.yml`.**
- [x] ~~Set up iSCSI off ZFS for K8s cluster storage~~ — **done. `democratic-csi` provides `iscsi-zfs` (default StorageClass) + `nfs-mergerfs`. See [ADR-015](../decisions/015-dynamic-storage-provisioning.md) and live cluster (`kubectl get sc`).**
- [x] ~~Set up S3-compatible storage~~ — **done 2026-04-01, migrated to two-tier 2026-04-03. MinIO Obs (hot, ZFS) at :9000/:9001 for Loki/Tempo. MinIO Bulk (cold, MergerFS) at :9002/:9003 for container registry and build artifacts. Deployed via `ansible/playbooks/deploy-foundation-stores.yml`. See ADR-003.**
- [x] ~~Set up foundation data stores~~ — **done 2026-04-01, migrated to ZFS 2026-04-03. PostgreSQL 16 (:5432), Redis 7 (:6379), MinIO Obs (:9000/:9001), MinIO Bulk (:9002/:9003) running as Docker Compose services. Hot services on ZFS at `/mnt/zfs/foundation/`, bulk on MergerFS at `/mnt/pool/foundation/`. Daily Postgres backup via pg_dumpall. See ADR-003.**
- [x] ~~Set up observability stack~~ — **done 2026-04-01, migrated to ZFS 2026-04-03. Prometheus (:9090), Alertmanager (:9093), Loki (:3100), Tempo (:3200), Grafana (:3000), Alloy deployed as Docker Compose services. Data on ZFS pool at `/mnt/zfs/observability/`. Loki/Tempo use MinIO Obs S3 backend, Grafana uses Postgres backend. Deployed via `ansible/playbooks/deploy-observability.yml`. See ADR-004.**
- [x] ~~Set up PXE boot server~~ — **superseded by [ADR-013](../decisions/013-local-disk-over-pxe-boot.md): K8s nodes boot from local disk, no PXE infrastructure. Simpler, faster, fewer moving parts. ADR-005 (NFS-root for PXE) is also superseded.**
- [ ] Configure R730 NIC (deferred with VLANs — see Phase 1C):
  - Port 1: VLAN 1 (general/management + internet)
  - Port 2: VLAN 10 (lab network)
  - Port 3-4: VLAN 20 (dedicated storage, if using storage VLAN)
- [x] ~~Set up iDRAC remote management~~ — **SSH racadm working at 10.0.0.203. Note: no Enterprise license, so no virtual media. HTTPS web UI works for basic monitoring.**
- ~~Install NetBird for VPN access~~ — **N/A: R730xd is internal-only; it terminates the dedicated WG ingress tunnel instead ([ADR-019](../decisions/019-ingress-and-tls-termination.md)).**
- [x] ~~Verify NFS is accessible from K8s nodes~~ — **done. `nfs-mergerfs` StorageClass live via `democratic-csi`.**
- [x] ~~**Stand up staging VM**~~ ([ADR-002 — Superseded](../decisions/002-r730-staging-vm-for-migration.md)) — **done 2026-03-28, decommissioned 2026-04-09. Served landing-page, caz-portfolio, resume-site during the cluster rebuild; all three moved back onto the new K8s cluster via Flux in Phase 7b (commits `7cb5af7`, `82555ec`, `3c984f7`). Staging VM teardown: commit `15d5f14`; playbooks preserved in `archive/staging-vm/`.**

### 2B: Quanta — K8s Worker

Notes: ADR-013 replaced diskless PXE boot with local-disk installs. Quanta now has a local boot SSD.

- [x] ~~Install 4-port NIC with PCIe riser~~ — **installed (2026-03-27).**
- [ ] Configure direct connection(s) from Quanta to R730 for dedicated NFS I/O — **deferred; current single-link performance is adequate and revisit alongside storage VLAN (Phase 1C).**
- [x] ~~Install OS~~ — **Debian installed via preseeded ISO.**
- [x] ~~Run baseline-setup Ansible playbook~~
- [x] ~~Configure networking~~
- [x] ~~Install container runtime (containerd)~~
- [x] ~~Join to K8s cluster~~ — **live worker on v1.33.10.**
- [x] ~~Verify node is Ready~~ — **`kubectl get nodes` shows quanta Ready.**
- [x] ~~Apply node labels~~

### 2C: Intel NUC — K8s Worker

Grandfather's NUC — thought to be bricked but the Intel ARC GPU was dead. Display output works via USB-C. i7-12700H (14C/20T) with 64 GB RAM makes it the second most powerful worker after Quanta.

- [x] ~~Install OS~~ — **Debian installed via preseeded ISO (local boot — has internal storage).**
- [x] ~~Run baseline-setup Ansible playbook~~
- [x] ~~Configure networking~~
- [x] ~~Install container runtime (containerd)~~
- [x] ~~Join to K8s cluster~~ — **live worker on v1.33.10.**
- [x] ~~Verify node is Ready~~
- [x] ~~Apply node labels~~

---

## Phase 3: K8s Cluster Migration

### 3A: Storage Cutover

See [ADR-004](../decisions/004-zfs-iscsi-for-k8s-storage.md) (architecture) and [ADR-015](../decisions/015-dynamic-storage-provisioning.md) (dynamic provisioning via democratic-csi).

- [x] ~~Set up ZFS pool on R730 (3×2TB drives from tower-pc)~~ — **done 2026-04-03 (pool `tank`, raidz1, `/mnt/zfs`).**
- [x] ~~Set up iSCSI target on R730 (off ZFS) for K8s block storage~~ — **done via `democratic-csi`.**
- [x] ~~Configure K8s iSCSI CSI driver / provisioner~~ — **done. `iscsi-zfs` is the default StorageClass; `nfs-mergerfs` also available.**
- [x] ~~Migrate existing PV data~~ — **no carryover from the old cluster: it was torn down and rebuilt. App PVCs are freshly provisioned by the CSI driver.**
- [x] ~~Update any hardcoded NFS references in manifests/Helm values~~ — **apps now use `iscsi-zfs` or `nfs-mergerfs` via StorageClass names, no hardcoded paths.**
- [x] ~~Verify PVCs are healthy and pods can read/write~~ — **all Flux HelmReleases Ready=True.**
- [x] ~~NFS on MergerFS remains available for bulk/non-latency-sensitive storage~~ — **`nfs-mergerfs` StorageClass live.**

### 3B: Migrate deb-web Services to K8s

The old Optiplex ("deb-web") services are resolved — the host has been fully committed to K8s worker duty.

- [x] ~~**Web hosting**~~ — **landing-page, caz-portfolio, and resume-site run in-cluster via Flux (Phase 7b, PRs #3/#4/#5).**
- [x] ~~**Palworld server**~~ — **decommissioned indefinitely ([ADR-022](../decisions/022-palworld-decommissioned.md)). Save data backed up; VPS UDP forward will be removed alongside this doc update.**
- [x] ~~**GitHub Actions runner**~~ — **old self-hosted runner retired; replaced by in-cluster ARC v2 ([ADR-017](../decisions/017-arc-v2-github-runners.md)) with a custom runner image built via Argo Workflows + Kaniko (Phase 8).**
- [x] ~~**Any other services**~~ — **none remaining; cloudflared and agent-docs-sync were dead weight and were dropped during the rebuild.**

### 3C: Optiplex Joins K8s

Notes: ADR-013 replaced diskless PXE boot with local-disk installs. Optiplex boots from local disk.

- [x] ~~Back up anything on Optiplex that isn't already migrated~~ — **Residuum + Palworld data to `~/Backups/deb-web/` (2026-04-03).**
- [x] ~~Install OS~~ — **Debian installed via preseeded ISO.**
- [x] ~~Run baseline-setup Ansible playbook~~
- [x] ~~Configure networking~~
- [x] ~~Install container runtime (containerd)~~
- [x] ~~Join to K8s cluster~~ — **live worker on v1.33.10.**
- [x] ~~Verify node is Ready~~
- [x] ~~Apply node labels~~

### 3D: Remove Old Workers

- [x] ~~Remove MSI laptop from K8s~~ — **done 2026-04-03. Hardware later given away; not in inventory.**
- [x] ~~Remove tower-pc from K8s~~ — **done 2026-04-03. Will rejoin the new cluster as a plain worker per [ADR-021](../decisions/021-off-the-shelf-router-tower-pc-as-worker.md).**
- [x] ~~Update Ansible inventory — remove MSI, handle tower-pc~~ — **MSI removed; tower-pc host entry also removed pending its actual join (re-added at join time).**
- [x] ~~Update VPS proxy config~~ — **VPS Caddy now routes `*.bearflinn.com` through the WG ingress tunnel to the K8s NodePort per [ADR-019](../decisions/019-ingress-and-tls-termination.md). Staging VM route retired.**

### 3E: Verify Cluster Health

- [x] ~~`kubectl get nodes`~~ — **Inspiron (control plane), Quanta / Intel NUC / Optiplex (workers), all Ready on v1.33.10.**
- [x] ~~All workloads running and healthy~~ — **`flux get kustomizations -A` and `flux get helmreleases -A` all `Ready=True`.**
- [x] ~~Ingress working (VPS → K8s → pods)~~ — **verified: landing.bearflinn.com, pennydreadfulsfx.com, resume.bearflinn.com all live.**
- [x] ~~PVCs healthy on new storage backends~~ — **iscsi-zfs (default) + nfs-mergerfs StorageClasses live.**
- [x] ~~CI/CD pipeline works (push → build → deploy)~~ — **ARC v2 runners + custom runner image, build/push to in-cluster registry, Flux reconcile (Phase 7–8).**

---

## Phase 4: Standalone Machines

### 4A: Tower PC — Plain K8s Worker (was: Router + GPU Inference)

**Revised** by [ADR-021](../decisions/021-off-the-shelf-router-tower-pc-as-worker.md): Tower PC will join as a plain K8s worker. No router role, no GPU role. The GPU inference fleet moves to a separate new-build host (tracked as "pending" in `current-hardware-inventory.md`). Routing moves to an off-the-shelf router when purchased.

- [x] ~~Shut down tower-pc from old cluster~~ — **done 2026-04-03 (see Phase 3D).**
- [x] ~~Migrate 3×2TB ZFS drives to R730~~ — **done 2026-04-03. Drives installed in bays 9+10+11, pool `tank` created.**
- [ ] Reinstall OS if needed (existing install may be usable)
- [ ] Run baseline-setup Ansible playbook
- [ ] Install container runtime (containerd)
- [ ] Add to `ansible/inventory/lab-nodes.yml` under `k8s_workers`
- [ ] Join to K8s cluster: `kubeadm join`
- [ ] Verify node Ready; apply node labels
- [ ] Ensure node-exporter / Alloy are scraping the box (observability coverage)

### 4D: AP630 — WiFi AP (Stock HiveOS)

~~Originally planned as Debian arm64 router ([ADR-003](../decisions/003-ap630-as-router.md)). Closed out — hardware bandwidth ceiling of 95 Mbps is not viable for GbE WAN routing ([ADR-010](../decisions/010-ap630-iudma-limit-requires-rdp.md), [ADR-011](../decisions/011-ap630-restored-to-stock-wifi-ap.md)).~~

Restored to stock HiveOS IQ Engine 10.6r7 on 2026-04-03. Now used as a WiFi AP alongside the AP230 and AP130s.

- [x] ~~Restored stock firmware~~ — **flashed via U-Boot TFTP from NAND backups (2026-04-03)**
- [ ] Configure SSID + security (standalone mode, `no capwap client enable`)
- [ ] Mount in optimal location for coverage
- [ ] Connect to SR2024 (PoE from switch)

### 4B: WiFi APs

- [x] ~~Flash/configure Aerohive APs for standalone mode~~ — **confirmed standalone via `no capwap client enable`. All 3 APs factory reset and CAPWAP disabled (2026-03-27).**
- [x] ~~AP630 restored to stock HiveOS~~ — **IQ Engine 10.6r7 (2026-04-03). See [ADR-011](../decisions/011-ap630-restored-to-stock-wifi-ap.md).**
- [ ] Mount AP230 in central location (starting with AP230 only — [ADR-009](../decisions/009-start-with-ap230-only.md))
- [ ] Mount AP630 for additional coverage (highest-performance AP: 4×4:4 MU-MIMO, 802.11ac Wave 2)
- [ ] Mount AP130(s) if coverage is still insufficient
- [ ] Connect APs to SR2024 (PoE from switch, no injectors needed)
- [ ] Configure SSID + password on each AP
- [ ] Test coverage throughout house
- [ ] Disable Xfinity gateway WiFi (once verified)

### 4C: MSI Laptop — Removed From Inventory

- [x] ~~Drain from K8s cluster~~ — **done 2026-03-26, force-deleted 2026-04-03.**
- [x] ~~MSI laptop given away.~~ — **hardware no longer owned. Not in inventory. The operator's on-the-go dev machine is a personal GS66 Stealth — not part of the homelab infra and intentionally not tracked here.**

---

## Phase 5: Cleanup & Documentation

- [x] ~~Add R730 to Ansible inventory~~ — **added as `storage_servers` group in `lab-nodes.yml` + dedicated `ansible/inventory/r730xd.yml`.**
- [x] ~~Add all lab machines to unified Ansible inventory~~ — **done. `ansible/inventory/lab-nodes.yml` covers r730xd + all K8s nodes.**
- [x] ~~Add Quanta to Ansible inventory~~ — **k8s_worker in `lab-nodes.yml`.**
- [x] ~~Add Intel NUC to Ansible inventory~~ — **k8s_worker in `lab-nodes.yml`.**
- [x] ~~Update Ansible inventory (`lab-nodes.yml`) with final topology~~ — **staging VM and MSI laptop removed. Tower PC will be added at join time per ADR-021.**
- [x] ~~Update `docs/` with new cluster topology~~ — **this pass: hardware-inventory, network-current, network-target, new-setup-planning, README all updated 2026-04-17.**
- [x] ~~Update `CLAUDE.md`~~ — **reviewed; no changes needed — CLAUDE.md contains operational rules and the ops-readiness checklist, not node tables.**
- [x] ~~Update VPS proxy inventory~~ — **Palworld UDP forward and `netbird_palworld_ip` removed (2026-04-17) alongside [ADR-022](../decisions/022-palworld-decommissioned.md).**
- [x] ~~Remove/archive old migration docs~~ — **staging VM playbooks archived (commit `15d5f14`); old cluster configs archived under `archive/pre-migration-2026/`.**
- [ ] Decommission old switches (5-port unmanaged × 2, 8-port unmanaged, 5-port managed) — cosmetic; the SR2024 is the live backbone.
- [x] ~~Commit all IaC changes~~ — **continuous; individual phase commits referenced in this doc.**

---

## Dependency Graph (historical)

Kept for reference. The original ordering was mostly followed; Phase 7 (app delivery via Flux) and Phase 8 (runner image, K8s upgrade) happened alongside Phase 3 rather than after Phase 4, because the staging VM held public traffic while the new cluster came up.

```
Phase 0 (parallel, no downtime) ──────── DONE
  ├── 0A: Hardware assessment
  ├── 0B: 3TB drive (mounted direct into pool, ADR-007)
  ├── 0C: Inventory services
  └── 0D: Gather supplies
         │
         v
Phase 1 (planned downtime) ───────────── DONE (VLANs deferred, UPS deferred)
  1A: Prepare closet
  1B: Run cable
  1C: SR2024 in place (VLANs → ADR-021 router)
  1D: Move existing machines
  1E: UPS (deferred)
         │
         v
Phase 2A: R730 storage ────────────────── DONE
   ├── Staging VM (ADR-002, superseded)
   └── Foundation + observability stacks
         │
         v
Phase 2B/2C: Quanta + Intel NUC join ──── DONE
         │
         v
Phase 3A: Storage cutover ─────────────── DONE (democratic-csi)
Phase 3B: deb-web services ────────────── DONE (Flux apps + Palworld ADR-022)
Phase 3C: Optiplex joins ──────────────── DONE
Phase 3D: Remove old workers ──────────── DONE (MSI given away; tower-pc pending rejoin)
Phase 3E: Verify cluster ──────────────── DONE (v1.33.10, Flux green)
         │
         ├──────────────────────┬───────────────────┐
         v                      v                   v
Phase 4A: Tower PC →        Phase 4B: APs      Phase 4D: AP630 stock
  plain K8s worker           (partial)          (restored, mount pending)
  (ADR-021)                      │
         │                       │
         └───────── Phase 5: Cleanup & docs ← this pass (2026-04-17)
```

Not on the original graph, added since the plan was written:

```
Phase 6  Ingress-nginx + cert-manager + WG tunnel (ADR-019) ──── DONE
Phase 7a Flux app delivery model (ADR-020) ────────────────────── DONE
Phase 7b Migrate landing-page / caz-portfolio / resume-site ──── DONE
Phase 8  K8s 1.33 upgrade, custom runner image, Argo, sccache ── DONE
```

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| ~~3TB drive data lost~~ | ~~High~~ | ~~Resolved: drive mounted directly into MergerFS pool ([ADR-007](../decisions/007-3tb-data-drive-direct-to-pool.md)). SnapRAID parity protects it.~~ |
| ~~R730 won't POST / dead hardware~~ | ~~Medium~~ | ~~Resolved: R730 online on Debian 13.4, iDRAC working.~~ |
| ~~Quanta won't POST~~ | ~~High~~ | ~~Resolved: Quanta is a live K8s worker on v1.33.10.~~ |
| ~~SR2024 VLAN issues~~ | ~~Medium~~ | ~~Resolved: VLANs, LACP, PoE all confirmed working. (VLAN config itself deferred — see Phase 1C.)~~ |
| ~~Aerohive APs can't run standalone~~ | ~~Low~~ | ~~Resolved: standalone mode confirmed on all APs (2026-03-27)~~ |
| ~~Tower PSU can't handle 3 GPUs~~ | ~~Medium~~ | ~~Confirmed insufficient. GPU fleet moves to a separate new-build host; Tower PC becomes plain K8s worker ([ADR-021](../decisions/021-off-the-shelf-router-tower-pc-as-worker.md)).~~ |
| ~~K8s cluster won't recover after move~~ | ~~Medium~~ | ~~Resolved: new cluster built from scratch (kubeadm + Flux); staging VM held public traffic during cutover.~~ |
| Power circuit overloaded | Medium | 2× 15A circuits in the closet, load balanced. Revisit if the GPU-inference host is high-draw. |
| Closet overheats | Medium | R730 + Quanta generate significant heat. Door open during heavy loads; revisit with active ventilation if sustained loads become typical. |

---

## Estimated Timeline

Not providing time estimates — too many unknowns (hardware viability, cable routing difficulty, debugging time). The phases are ordered by dependency, not schedule. Phase 0 can start immediately.
