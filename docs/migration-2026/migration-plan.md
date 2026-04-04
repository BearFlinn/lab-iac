# Migration Plan

> **IP addresses:** Authoritative values are in `ansible/group_vars/all/network.yml`.

Last updated: 2026-04-03

## Guiding Principles

- **Current cluster stays functional** until new infrastructure is ready to take over
- **Data safety first** — ~~back up the 3TB drive before touching any storage~~ (resolved — [ADR-007](../decisions/007-3tb-data-drive-direct-to-pool.md))
- **Network before compute** — machines need connectivity before they can be configured
- **One role at a time** — don't drain a machine from K8s until its replacement is confirmed working

---

## Migration Strategy

**Staging approach:** Before tearing down the current K8s cluster, stand up critical workloads in a temporary VM (on R730 or Raspberry Pi on hand) so they stay available throughout the migration. This removes time pressure from the cluster rebuild.

**Anchor machine:** The R730 comes online first — basic OS, staging VM for critical services, then PXE server and storage. Everything else gets shuffled around it.

---

## Phase 0: Assessment & Prep (No Downtime)

Do all of this before touching the physical setup. Can be done in parallel.

### 0A: Hardware Assessment

- [x] ~~Test POST on R730xd~~ — **confirmed. BIOS 2.3.4, iDRAC accessible.**
- [x] ~~Identify R730xd CPU~~ — **Intel Xeon E5-2630 v3 (8C/16T @ 2.4 GHz, 85W)**
- [x] ~~Check R730xd drive bay config~~ — **12× 3.5" front + 2× 2.5" rear confirmed**
- [x] ~~Remove 3TB drive from mini PC~~ — **physically removed 2026-03-26, data migration deferred until R730 online**
- [x] ~~Test POST on Quanta~~ — **confirmed. AMI BIOS, boots to EFI shell (no drives).**
- [x] ~~Identify Quanta CPUs~~ — **2× Intel Xeon E5-2670 (Sandy Bridge-EP), 8C/16T each = 16C/32T total @ 2.6 GHz**
- [x] ~~Check Quanta drive bays~~ — **6× SATA, no hot-swap bays, internal mount only, currently empty**
- [x] ~~Configure Quanta BMC/IPMI~~ — **static IP set, dedicated NIC port**
- [ ] **Verify Quanta sine wave tolerance** — will it run on the APC UPS or does it need pure sine? **Deferred — will test when physically setting up in closet.**
- [ ] **Audit Tower PC PSU** — wattage, available PCIe power connectors (6-pin, 8-pin), number of PCIe x16 slots. **Blocked until Phase 3** — tower is currently primary K8s worker (handles majority of workload post-MSI drain)
- [x] ~~Test SR2024 switch~~ — **fully operational. VLANs, LACP, PoE all confirmed. Currently in use powering APs and providing lab connectivity.**
- [x] ~~Check Aerohive AP + switch firmware~~ — **confirmed standalone capable, no cloud dependency (per previous owner)**
- [ ] **Check UPS** — APC RJ45-to-USB data cable still needed for NUT monitoring. **Deferred — not blocking migration.**

### 0B: Data Safety

- [x] ~~Back up critical data before migration:~~
  - ~~3TB drive (removed from mini PC 2026-03-26)~~ — **mounted directly into R730xd MergerFS pool (bay 8). Data preserved in-place, no separate backup needed. See [ADR-007](../decisions/007-3tb-data-drive-direct-to-pool.md).**
  - [ ] Palworld server data (deb-web) — save files, config
  - [ ] Residuum files (deb-web)
  - Everything else is stale or expendable (tower-pc ZFS pool ~9MB, deb-web duplicate apps)

### 0C: Inventory Current Services

Document everything that's running so nothing gets lost in the migration:

- [x] ~~K8s workloads~~ — **inventoried. 10 app deployments + infra (ingress, cert-manager, registry, NFS provisioner, actions runner).**
- [x] ~~deb-web (Optiplex) services~~ — **inventoried. Running duplicate Docker Compose copies of most K8s apps, plus Prometheus/Grafana monitoring stack, Palworld (systemd), Caddy, cloudflared, GitHub Actions runner, agent-docs-sync.**
- [x] ~~Tower-pc services~~ — **NFS export at /mnt/nfs-storage (bcache-backed 1TB HDD). ZFS pool had appeared DEGRADED but all 3×2TB drives are healthy — the setup script targeted a card reader slot (/dev/sdg) instead of the third drive (/dev/sdd). ~9MB data. No Docker containers. No extra services.**
- [x] ~~MSI laptop workloads~~ — **Nothing custom — just kubelet/containerd. Hosts 18 of ~25 pods (most K8s workloads schedule here). Clean removal.**
- [ ] **DNS/networking dependencies** — what breaks if IPs change? (NFS export references `<lab_subnet>` + NetBird IP 172.30.186.199; VPS proxy routes to K8s ingress via NetBird)
- [x] ~~Ansible vault~~ — **.vault_pass exists (45 bytes). Ensure backed up outside repo.**
- [x] ~~cloudflared on deb-web~~ — **dead, can be removed**
- [x] ~~agent-docs-sync on deb-web~~ — **trivial, nearly unused, can be dropped**

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
- [ ] Closet ↔ AP230 location (starting with AP230 only — see [ADR-009](../decisions/009-start-with-ap230-only.md))
- [ ] Closet ↔ Xfinity gateway (living room) — uplink (if not already routed through switch chain)

### 1C: Set Up Switch & Network

Tower PC resumes the router role ([ADR-011](../decisions/011-ap630-restored-to-stock-wifi-ap.md) — AP630 router project closed out, device restored to stock HiveOS as WiFi AP). VLANs and final switch config depend on the Tower PC being set up as router.

- [x] ~~Initial closet networking~~ — **5-port managed switch relocated to closet (2026-03-26). Current K8s machines + desktop on 8-port unmanaged switch.**
- [ ] Mount SR2024 in closet (replaces temporary 5-port managed switch)
- [ ] Connect Xfinity uplink to switch
- [ ] Configure VLANs on SR2024:
  - VLAN 1 (default/untagged): Home network — Xfinity DHCP, bedroom, garage, APs
  - VLAN 10 (tagged): Lab — all lab machines
  - VLAN 20 (tagged, optional): Storage — R730 ↔ K8s nodes dedicated iSCSI/NFS traffic
- [ ] Assign switch ports
- [ ] Test connectivity: machine on switch can reach internet via Xfinity gateway

### 1D: Move Existing Machines

- [x] ~~Drain MSI laptop from K8s~~ — **done 2026-03-26. Scaled down non-essential workloads (residuum-landing, coaching-website, family-dashboard, game-server-platform, advocacy-quiz, zork) to 0 replicas. Kept landing-page, resume-site, caz-portfolio, and actions-runner-controller running. Remaining pods drained to tower-pc. Node cordoned.**
- [ ] **Drain Tower PC from K8s** — `kubectl drain tower-pc --ignore-daemonsets --delete-emptydata`
- [ ] Shut down all cluster machines gracefully
- [ ] Physically move Inspiron, Optiplex to closet
- [ ] Physically move Tower PC to closet (or nearby)
- [ ] Connect all moved machines to SR2024
- [ ] Boot Inspiron (control plane) first, verify K8s API comes up
- [ ] Verify Optiplex connectivity

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
- [ ] Set up iSCSI off ZFS for K8s cluster storage (replacing NFS for performance) — see [ADR-004](../decisions/004-zfs-iscsi-for-k8s-storage.md)
- [x] ~~Set up S3-compatible storage~~ — **done 2026-04-01, migrated to two-tier 2026-04-03. MinIO Obs (hot, ZFS) at :9000/:9001 for Loki/Tempo. MinIO Bulk (cold, MergerFS) at :9002/:9003 for container registry and build artifacts. Deployed via `ansible/playbooks/deploy-foundation-stores.yml`. See ADR-003.**
- [x] ~~Set up foundation data stores~~ — **done 2026-04-01, migrated to ZFS 2026-04-03. PostgreSQL 16 (:5432), Redis 7 (:6379), MinIO Obs (:9000/:9001), MinIO Bulk (:9002/:9003) running as Docker Compose services. Hot services on ZFS at `/mnt/zfs/foundation/`, bulk on MergerFS at `/mnt/pool/foundation/`. Daily Postgres backup via pg_dumpall. See ADR-003.**
- [x] ~~Set up observability stack~~ — **done 2026-04-01, migrated to ZFS 2026-04-03. Prometheus (:9090), Alertmanager (:9093), Loki (:3100), Tempo (:3200), Grafana (:3000), Alloy deployed as Docker Compose services. Data on ZFS pool at `/mnt/zfs/observability/`. Loki/Tempo use MinIO Obs S3 backend, Grafana uses Postgres backend. Deployed via `ansible/playbooks/deploy-observability.yml`. See ADR-004.**
- [ ] Set up PXE boot server (TFTP/DHCP) for diskless K8s nodes (Inspiron, Optiplex, Quanta) — NFS-root off ZFS, see [ADR-005](../decisions/005-nfs-root-for-pxe-nodes.md)
- [ ] Configure R730 NIC:
  - Port 1: VLAN 1 (general/management + internet)
  - Port 2: VLAN 10 (lab network)
  - Port 3-4: VLAN 20 (dedicated storage, if using storage VLAN)
- [x] ~~Set up iDRAC remote management~~ — **SSH racadm working at `<r730xd_idrac_ip>`. Note: no Enterprise license, so no virtual media. HTTPS web UI works for basic monitoring.**
- [ ] Install NetBird for VPN access
- [ ] Verify NFS is accessible from K8s nodes
- [x] ~~**Stand up staging VM**~~ ([ADR-002](../decisions/002-r730-staging-vm-for-migration.md)) — **done 2026-03-28. Debian 13 VM on libvirt NAT network (`<staging_vm_ip>`), 4 vCPU / 8GB RAM. KVM/libvirt installed via `ansible/roles/r730xd-vm-host`, VM provisioned via `ansible/playbooks/create-staging-vm.yml`. Uses Debian generic cloud image + cloud-init + UEFI boot. Docker, gh CLI, and NetBird installed. Critical services deployed via `ansible/playbooks/deploy-staging-services.yml`:**
  - **landing-page** (nginx) — landing.bearflinn.com
  - **caz-portfolio** (Rust) — pennydreadfulsfx.com
  - **resume-site** (FastAPI + pgvector/pg16) — resume.bearflinn.com
  - **Caddy reverse proxy on port 80, routes by Host header. All repos cloned from grizzly-endeavors org, built from source on VM.**
  - [ ] Update VPS proxy to route traffic to staging VM (staging VM NetBird IP:80)
  - [ ] Verify all critical services are reachable from public internet before proceeding to Phase 3

### 2B: Quanta — K8s Worker (Diskless)

- [x] ~~Install 4-port NIC with PCIe riser~~ — **installed (2026-03-27)** (no local storage — PXE boot from R730)
- [ ] Configure direct connection(s) from Quanta to R730 for dedicated NFS I/O
- [ ] PXE boot OS from R730
- [ ] Run baseline-setup Ansible playbook
- [ ] Configure networking (VLAN 1 + VLAN 10, match K8s node config)
- [ ] Install NetBird
- [ ] Install container runtime (containerd)
- [ ] Join to K8s cluster: `kubeadm join`
- [ ] Verify node is Ready: `kubectl get nodes`
- [ ] Apply node labels

---

## Phase 3: K8s Cluster Migration

### 3A: Storage Cutover

See [ADR-004](../decisions/004-zfs-iscsi-for-k8s-storage.md) and [ADR-005](../decisions/005-nfs-root-for-pxe-nodes.md) for storage architecture decisions.

- [x] ~~Set up ZFS pool on R730 (3×2TB drives from tower-pc) for latency-sensitive storage~~ — **done 2026-04-03 (pool `tank`, raidz1, `/mnt/zfs`)**
- [ ] Set up iSCSI target on R730 (off ZFS) for K8s block storage
- [ ] Configure K8s iSCSI CSI driver / provisioner
- [ ] Migrate existing PV data from tower-pc NFS to R730
- [ ] Update any hardcoded NFS references in manifests/Helm values
- [ ] Verify PVCs are healthy and pods can read/write
- [ ] NFS on MergerFS remains available for bulk/non-latency-sensitive storage

### 3B: Migrate deb-web Services to K8s

Before the Optiplex can be wiped and joined to K8s, its services need new homes:

- [ ] **Web hosting** — containerize and deploy to K8s (or move to R730 if static sites)
- [ ] **Palworld server** — containerize and deploy to K8s (or run on R730 as a VM/container)
  - Update VPS UDP forwarding rule to point to new location
- [ ] **GitHub Actions runner** — already has K8s manifests in the cluster, verify it works on new nodes
- [ ] **Any other services** — identified in Phase 0C

### 3C: Optiplex Joins K8s (Diskless)

- [ ] Back up anything on Optiplex that isn't already migrated
- [ ] Remove SSD — repurpose to jumpbox
- [ ] PXE boot OS from R730
- [ ] Run baseline-setup Ansible playbook
- [ ] Configure networking (VLAN 1 + VLAN 10)
- [ ] Install NetBird
- [ ] Install container runtime (containerd)
- [ ] Join to K8s cluster: `kubeadm join`
- [ ] Verify node is Ready
- [ ] Apply node labels

### 3D: Remove Old Workers

- [ ] Remove MSI laptop from K8s: `kubectl delete node msi-laptop`
- [ ] Remove tower-pc from K8s: `kubectl delete node tower-pc`
- [ ] Update Ansible inventory — remove MSI, move tower-pc out of k8s_workers
- [ ] Update VPS proxy config if any NetBird IPs changed

### 3E: Verify Cluster Health

- [ ] `kubectl get nodes` — Inspiron (control plane), Quanta (worker), Optiplex (worker)
- [ ] All workloads running and healthy
- [ ] Ingress working (VPS → NetBird → K8s → pods)
- [ ] PVCs healthy on new NFS backend
- [ ] CI/CD pipeline works (push → build → deploy)

---

## Phase 4: Standalone Machines

### 4A: Tower PC — GPU Inference Workstation

Tower PC serves as both router and GPU inference workstation ([ADR-001](../decisions/001-tower-pc-as-router.md), reinstated by [ADR-011](../decisions/011-ap630-restored-to-stock-wifi-ap.md)).

- [ ] Shut down tower-pc (critical workloads already on R730 staging VM from Phase 2A)
- [x] ~~Migrate 3×2TB ZFS drives to R730 (for latency-sensitive ZFS/iSCSI pool)~~ — **done 2026-04-03. Drives installed in bays 9+10+11, pool `tank` created.**
- [ ] Install GPUs: 1080 Ti + 1050 Ti (keep existing 1060)
  - Verify PSU can handle the load (1080 Ti alone is ~250W)
  - Verify PCIe slot spacing for triple GPU
- [ ] Reinstall OS (or repurpose existing install)
- [ ] Configure routing: nftables NAT, DHCP (dnsmasq), DNS
- [ ] Connect WAN (Xfinity gateway in bridge mode) + LAN (SR2024) on separate NICs
- [ ] Replace Xfinity gateway's routing role
- [ ] Install NVIDIA drivers
- [ ] Install inference stack (Ollama, vLLM, or text-generation-inference)
- [ ] Configure API access from other machines on the lab VLAN

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

### 4C: MSI Laptop — Dev Machine

- [x] ~~Drain from K8s cluster~~ — **done 2026-03-26. Node cordoned, workloads migrated to tower-pc.**
- [ ] Remove K8s components (kubeadm reset, remove containerd)
- [ ] Fresh OS install or cleanup
- [ ] Set up development environment
- [ ] Done — no longer part of infrastructure

---

## Phase 5: Cleanup & Documentation

- [x] ~~Add R730 to Ansible inventory~~ — **added as `storage_servers` group in `all-nodes.yml` + dedicated `ansible/inventory/r730xd.yml`**
- [x] ~~Add all lab machines to unified Ansible inventory~~ — **done 2026-03-28. `ansible/inventory/lab-nodes.yml` covers r730xd, tower-pc, dell-inspiron-15, optiplex, staging-vm with group structure (k8s_cluster, standalone, storage_servers, staging). All machines SSH-verified.**
- [ ] Add Quanta to Ansible inventory (pending PXE boot / OS install)
- [ ] Update Ansible inventory (`all-nodes.yml`) with final topology
- [ ] Update `docs/ARCHITECTURE.md` with new cluster topology
- [ ] Update `CLAUDE.md` with new node table, IPs, roles
- [ ] Update VPS proxy inventory if any endpoints changed
- [ ] Remove/archive old migration docs
- [ ] Decommission old switches (5-port unmanaged × 2, 8-port unmanaged, 5-port managed)
- [ ] Commit all IaC changes

---

## Dependency Graph

```
Phase 0 (all parallel, no downtime)
  ├── 0A: Hardware assessment
  ├── 0B: Back up 3TB drive ──────────── DONE (mounted directly into pool)
  ├── 0C: Inventory services
  └── 0D: Gather supplies
         │
         v
Phase 1 (planned downtime)
  1A: Prepare closet
  1B: Run cable
  1C: Set up switch ──────────────────── Network must work before anything else
  1D: Move existing machines
  1E: UPS setup
         │
         ├─────────────────┐
         v                 v
Phase 2A: R730 storage   Phase 2B: Quanta joins K8s
         │                 │
         v                 │
  Staging VM on R730 ────── Critical services move here, unblocks tower-pc
         │                 │
         v                 │
Phase 3A: Storage cutover  │
         │                 │
         v                 v
Phase 3B: Migrate deb-web services
         │
         v
Phase 3C: Optiplex joins K8s
         │
         v
Phase 3D: Remove old workers (incl. tower-pc)
         │
         v
Phase 3E: Verify cluster
         │
         ├──────────────────────┬──────────────────┐
         v                      v                  v
Phase 4A: Tower PC →       Phase 4B: WiFi APs  Phase 4D: AP630 →
  Router + GPU inference        │                WiFi AP (stock)
         │                      │                  │
         v                      v                  v
Phase 5: Cleanup & documentation (tear down staging VM)
```

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| ~~3TB drive data lost~~ | ~~High~~ | ~~Resolved: drive mounted directly into MergerFS pool ([ADR-007](../decisions/007-3tb-data-drive-direct-to-pool.md)). SnapRAID parity protects it.~~ |
| R730 won't POST / dead hardware | Medium | Test in Phase 0A before planning around it |
| Quanta won't POST | High | Test in Phase 0A — if dead, need to restructure (tower stays as K8s worker?) |
| ~~SR2024 VLAN issues~~ | ~~Medium~~ | ~~Resolved: VLANs, LACP, PoE all confirmed working (2026-03-27)~~ |
| ~~Aerohive APs can't run standalone~~ | ~~Low~~ | ~~Resolved: standalone mode confirmed on all 3 APs (2026-03-27)~~ |
| Tower PSU can't handle 3 GPUs | Medium | Test in Phase 0A. Fallback: only 2 GPUs, or upgrade PSU |
| K8s cluster won't recover after move | Medium | Take etcd backup before Phase 1D. Worst case: rebuild cluster (Ansible playbooks exist) |
| Power circuit overloaded | High | Assess total draw in Phase 0A. May need dedicated circuit for closet |
| Closet overheats | Medium | R730 + Quanta generate significant heat. May need ventilation or door vents |

---

## Estimated Timeline

Not providing time estimates — too many unknowns (hardware viability, cable routing difficulty, debugging time). The phases are ordered by dependency, not schedule. Phase 0 can start immediately.
