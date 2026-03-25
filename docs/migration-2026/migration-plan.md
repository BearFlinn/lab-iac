# Migration Plan

Last updated: 2026-03-24

## Guiding Principles

- **Current cluster stays functional** until new infrastructure is ready to take over
- **Data safety first** — back up the 3TB drive before touching any storage
- **Network before compute** — machines need connectivity before they can be configured
- **One role at a time** — don't drain a machine from K8s until its replacement is confirmed working

---

## Phase 0: Assessment & Prep (No Downtime)

Do all of this before touching the physical setup. Can be done in parallel.

### 0A: Hardware Assessment

- [x] ~~Test POST on R730xd~~ — **confirmed. BIOS 2.3.4, iDRAC accessible.**
- [x] ~~Identify R730xd CPU~~ — **Intel Xeon E5-2630 v3 (8C/16T @ 2.4 GHz, 85W)**
- [x] ~~Check R730xd drive bay config~~ — **12× 3.5" front + 2× 2.5" rear confirmed**
- [x] ~~Test POST on Quanta~~ — **confirmed. AMI BIOS, boots to EFI shell (no drives).**
- [x] ~~Identify Quanta CPUs~~ — **2× Intel Xeon E5-2670 (Sandy Bridge-EP), 8C/16T each = 16C/32T total @ 2.6 GHz**
- [x] ~~Check Quanta drive bays~~ — **6× SATA, no hot-swap bays, internal mount only, currently empty**
- [x] ~~Configure Quanta BMC/IPMI~~ — **static IP set, dedicated NIC port**
- [ ] **Verify Quanta sine wave tolerance** — will it run on the APC UPS or does it need pure sine?
- [ ] **Audit Tower PC PSU** — wattage, available PCIe power connectors (6-pin, 8-pin), number of PCIe x16 slots
- [ ] **Test SR2024 switch** — power on, access management interface, confirm VLAN support, test ports
- [x] ~~Check Aerohive AP + switch firmware~~ — **confirmed standalone capable, no cloud dependency (per previous owner)**
- [ ] **Check UPS** — does the APC cable (RJ45-to-USB) exist or need to be sourced?

### 0B: Data Safety

- [ ] **Back up critical data before migration:**
  - 3TB drive on mini PC — **still a blocker**, but can bootstrap R730xd with some 4TB drives first, then back up 3TB there
  - Palworld server data (deb-web) — save files, config
  - Residuum files (deb-web)
  - Everything else is stale or expendable (tower-pc ZFS pool ~9MB, deb-web duplicate apps)

### 0C: Inventory Current Services

Document everything that's running so nothing gets lost in the migration:

- [x] ~~K8s workloads~~ — **inventoried. 10 app deployments + infra (ingress, cert-manager, registry, NFS provisioner, actions runner).**
- [x] ~~deb-web (Optiplex) services~~ — **inventoried. Running duplicate Docker Compose copies of most K8s apps, plus Prometheus/Grafana monitoring stack, Palworld (systemd), Caddy, cloudflared, GitHub Actions runner, agent-docs-sync.**
- [x] ~~Tower-pc services~~ — **NFS export at /mnt/nfs-storage (bcache-backed 1TB HDD). ZFS pool DEGRADED (1 of 3 drives missing, ~9MB data). No Docker containers. No extra services.**
- [x] ~~MSI laptop workloads~~ — **Nothing custom — just kubelet/containerd. Hosts 18 of ~25 pods (most K8s workloads schedule here). Clean removal.**
- [ ] **DNS/networking dependencies** — what breaks if IPs change? (NFS export references 10.0.0.0/24 + NetBird IP 172.30.186.199; VPS proxy routes to K8s ingress via NetBird)
- [x] ~~Ansible vault~~ — **.vault_pass exists (45 bytes). Ensure backed up outside repo.**
- [x] ~~cloudflared on deb-web~~ — **dead, can be removed**
- [x] ~~agent-docs-sync on deb-web~~ — **trivial, nearly unused, can be dropped**

### 0D: Gather Supplies

- [x] ~~Ethernet cable~~ — **~300ft cat6 on hand**
- [x] ~~PoE for APs~~ — **switch has 12 PoE ports, no injectors needed**
- [ ] APC RJ45-to-USB data cable (940-0127 or compatible)
- [x] ~~Power strips~~ — **on hand**
- [x] ~~Closet power~~ — **dedicated 20A circuit**
- [ ] RJ45-to-USB console cable for Aerohive AP/switch configuration
- [ ] PCIe riser for Quanta (needed to install 4-port NIC — Quanta has no onboard RJ45)

---

## Phase 1: Physical Infrastructure (Planned Downtime)

This is the big move. The current cluster goes down, everything gets relocated.

### 1A: Prepare the Closet

- [ ] Install shelving or rack (even a basic wire rack works)
- [ ] Run power to closet (verify circuit capacity — R730 + Quanta + tower could pull 1kW+)
- [ ] Position UPS on bottom shelf
- [ ] Plan physical layout:
  - UPS (bottom)
  - R730 + Quanta (heaviest, lowest possible)
  - SR2024 switch (accessible for patching)
  - Optiplex + Inspiron (lighter, higher shelf)
  - Tower PC (nearby or in closet depending on noise/heat)

### 1B: Run Cable

- [ ] Closet ↔ Xfinity gateway (living room) — uplink
- [ ] Closet ↔ Master bedroom — sibling's drop
- [ ] Closet ↔ Garage/workshop
- [ ] Closet ↔ AP locations (×3, or start with 1 and expand)
- [ ] Test every run with a cable tester before connecting

### 1C: Set Up Switch & Network

- [ ] Mount SR2024 in closet
- [ ] Connect Xfinity uplink to switch
- [ ] Configure VLANs on SR2024:
  - VLAN 1 (default/untagged): Home network — Xfinity DHCP, bedroom, garage, APs
  - VLAN 10 (tagged): Lab — all lab machines
  - VLAN 20 (tagged, optional): Storage — R730 ↔ K8s nodes dedicated NFS traffic
- [ ] Assign switch ports:
  - Uplink to Xfinity: VLAN 1 untagged
  - Bedroom/Garage drops: VLAN 1 untagged
  - AP ports: VLAN 1 untagged (upgrade to trunk later when router arrives)
  - Lab machines: trunk ports (VLAN 1 untagged + VLAN 10 tagged)
  - R730 storage port(s): VLAN 20 access (if using storage VLAN)
- [ ] Test connectivity: machine on switch can reach internet via Xfinity gateway

### 1D: Move Existing Machines

- [ ] **Drain MSI laptop from K8s** — `kubectl drain msi-laptop --ignore-daemonsets --delete-emptydata`
- [ ] **Drain Tower PC from K8s** — `kubectl drain tower-pc --ignore-daemonsets --delete-emptydata`
- [ ] Shut down all cluster machines gracefully
- [ ] Physically move Inspiron, Optiplex to closet
- [ ] Physically move Tower PC to closet (or nearby)
- [ ] Connect all moved machines to SR2024
- [ ] Boot Inspiron (control plane) first, verify K8s API comes up
- [ ] Verify Optiplex connectivity

### 1E: UPS Setup

- [ ] Connect UPS in closet
- [ ] Plug in: Inspiron, Optiplex, SR2024 switch (battery-backed outlets)
- [ ] Plug in: R730, Quanta, Tower PC on surge-only outlets (or separate power strip)
- [ ] Connect UPS data cable to Inspiron or Optiplex (whichever is most stable)
- [ ] Install and configure NUT server on the connected machine
- [ ] Test: pull power, verify UPS kicks in and NUT reports status

---

## Phase 2: New Machines Online

### 2A: R730 — Storage Server

- [ ] Install drives in R730xd:
  - Boot: 240GB SATA SSD (from tower-pc) in rear 2.5" bay
  - Initial data drives: start with some 4TB drives, get online, back up 3TB drive
  - Remaining drives after backup: rest of 4TBs + 3TBs + optionally tower-pc's 3×2TB ZFS drives
- [ ] Install OS (Proxmox? Debian + ZFS? TrueNAS?)
- [ ] Configure storage pools:
  - Main pool from the large drives
  - Decide on filesystem/RAID level (ZFS RAID-Z2 recommended for this many drives)
- [ ] Set up NFS exports for K8s PVCs
- [ ] Set up S3-compatible storage if needed (Garage or MinIO)
- [ ] Configure R730 NIC:
  - Port 1: VLAN 1 (general/management + internet)
  - Port 2: VLAN 10 (lab network)
  - Port 3-4: VLAN 20 (dedicated storage, if using storage VLAN)
- [ ] Set up iDRAC remote management
- [ ] Install NetBird for VPN access
- [ ] Verify NFS is accessible from K8s nodes

### 2B: Quanta — K8s Worker

- [ ] Install 250GB SSD (spare) + 4-port NIC with riser
- [ ] Install OS (Ubuntu Server or Debian — match existing cluster OS)
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

- [ ] Update K8s NFS provisioner to point to R730 instead of tower-pc
- [ ] Migrate existing PV data from tower-pc NFS to R730 NFS
- [ ] Update any hardcoded NFS references in manifests/Helm values
- [ ] Verify PVCs are healthy and pods can read/write

### 3B: Migrate deb-web Services to K8s

Before the Optiplex can be wiped and joined to K8s, its services need new homes:

- [ ] **Web hosting** — containerize and deploy to K8s (or move to R730 if static sites)
- [ ] **Palworld server** — containerize and deploy to K8s (or run on R730 as a VM/container)
  - Update VPS UDP forwarding rule to point to new location
- [ ] **GitHub Actions runner** — already has K8s manifests in the cluster, verify it works on new nodes
- [ ] **Any other services** — identified in Phase 0C

### 3C: Optiplex Joins K8s

- [ ] Back up anything on Optiplex that isn't already migrated
- [ ] Wipe and reinstall OS
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

- [ ] Shut down tower-pc
- [ ] Migrate ZFS drives to R730 (if not done in Phase 2A)
- [ ] Install GPUs: 1080 Ti + 1050 Ti (keep existing 1060)
  - Verify PSU can handle the load (1080 Ti alone is ~250W)
  - Verify PCIe slot spacing for triple GPU
- [ ] Reinstall OS (or repurpose existing install)
- [ ] Install NVIDIA drivers
- [ ] Install inference stack (Ollama, vLLM, or text-generation-inference)
- [ ] Configure API access from other machines on the lab VLAN
- [ ] Connect to UPS (battery-backed outlet)

### 4B: WiFi APs

- [ ] Flash/configure Aerohive APs for standalone mode (if possible)
- [ ] Mount AP230 in central location
- [ ] Mount AP130(s) for coverage extension
- [ ] Connect to SR2024 via PoE injectors
- [ ] Configure SSID + password
- [ ] Test coverage throughout house
- [ ] Disable Xfinity gateway WiFi (once verified)

### 4C: MSI Laptop — Dev Machine

- [ ] Remove K8s components (kubeadm reset, remove containerd)
- [ ] Fresh OS install or cleanup
- [ ] Set up development environment
- [ ] Done — no longer part of infrastructure

---

## Phase 5: Cleanup & Documentation

- [ ] Update Ansible inventory (`all-nodes.yml`) with new topology
- [ ] Add R730 and Quanta to Ansible inventory (standalone or K8s groups)
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
  ├── 0B: Back up 3TB drive ──────────── HARD BLOCKER for any drive work
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
Phase 3A: Storage cutover  │
         │                 │
         v                 v
Phase 3B: Migrate deb-web services
         │
         v
Phase 3C: Optiplex joins K8s
         │
         v
Phase 3D: Remove old workers
         │
         v
Phase 3E: Verify cluster
         │
         ├──────────────────────┐
         v                      v
Phase 4A: Tower PC → GPU    Phase 4B: WiFi APs
         │                      │
         v                      v
Phase 5: Cleanup & documentation
```

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| 3TB drive data lost | High | Back up FIRST in Phase 0B, verify backup before proceeding |
| R730 won't POST / dead hardware | Medium | Test in Phase 0A before planning around it |
| Quanta won't POST | High | Test in Phase 0A — if dead, need to restructure (tower stays as K8s worker?) |
| SR2024 VLAN issues | Medium | Test in Phase 0A. Fallback: flat network, still an upgrade over daisy-chain |
| Aerohive APs can't run standalone | Low | Fallback: keep Xfinity WiFi, use D-Link as OpenWrt AP, or buy cheap AP |
| Tower PSU can't handle 3 GPUs | Medium | Test in Phase 0A. Fallback: only 2 GPUs, or upgrade PSU |
| K8s cluster won't recover after move | Medium | Take etcd backup before Phase 1D. Worst case: rebuild cluster (Ansible playbooks exist) |
| Power circuit overloaded | High | Assess total draw in Phase 0A. May need dedicated circuit for closet |
| Closet overheats | Medium | R730 + Quanta generate significant heat. May need ventilation or door vents |

---

## Estimated Timeline

Not providing time estimates — too many unknowns (hardware viability, cable routing difficulty, debugging time). The phases are ordered by dependency, not schedule. Phase 0 can start immediately.
