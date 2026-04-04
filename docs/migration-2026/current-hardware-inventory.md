# Current Hardware Inventory

> **IP addresses:** Authoritative values are in `ansible/group_vars/all/network.yml`.

Last updated: 2026-04-02

---

## Active K8s Cluster Nodes

### dell-inspiron-15 — Control Plane

| Spec | Value |
|------|-------|
| Model | Dell Inspiron 15-3567 |
| Form factor | Laptop |
| CPU | Intel i3-7100U — 2C/4T @ 2.7 GHz |
| RAM | 8 GB |
| Storage | 256 GB SSD (to be removed — repurposed to jumpbox) |
| GPU | None |
| Network | enp2s0, IP `<dell_inspiron_ip>` |
| Current role | K8s control plane (single-node etcd, apiserver, scheduler, controller-manager) |
| Migration note | Will PXE boot from R730 (diskless). SSD repurposed to jumpbox. |

### tower-pc — Worker

| Spec | Value |
|------|-------|
| Model | Custom full tower |
| Form factor | Full tower |
| CPU | Intel i7-4790 — 4C/8T @ 3.6–4.0 GHz |
| RAM | 24 GB |
| Storage | 128 GB NVMe (bcache backing), 240 GB SATA SSD (OS), 1 TB HDD (NFS), 3×2 TB HDD (all healthy — ZFS pool appeared degraded due to setup script targeting a card reader instead of the 3rd drive) — **~6.4 TB total raw** |
| GPU | NVIDIA GTX 1060 3 GB |
| Network | eno1, IP `<tower_pc_ip>` |
| Current role | K8s worker — NFS server, storage services, GPU workloads |

### msi-laptop — Worker (REMOVING)

| Spec | Value |
|------|-------|
| Model | MSI GS43VR 6RE Phantom Pro |
| Form factor | Laptop |
| CPU | Intel i7-6700HQ — 4C/8T @ 2.6–3.5 GHz |
| RAM | 32 GB |
| Storage | 1 TB SSD + 1 TB HDD — **2 TB total** |
| GPU | NVIDIA GTX 1060 3 GB |
| Network | enp61s0, IP 10.0.0.177 (decommissioned — see MEMORY.md) |
| Current role | K8s worker — monitoring/observability workloads |
| Migration note | **Being removed from cluster to repurpose as a development machine.** Workloads must be migrated before removal. |

## Inactive / Pending Nodes

### dell-optiplex-9020 (deb-web)

| Spec | Value |
|------|-------|
| Model | Dell Optiplex 9020 |
| Form factor | SFF desktop |
| CPU | Intel i7-4790 — 4C/8T |
| RAM | 32 GB |
| Storage | 512 GB SSD (to be removed — repurposed to jumpbox) |
| GPU | None |
| Network | IP not currently assigned in cluster |
| Current role | **Not in K8s cluster.** Currently runs as `deb-web` — barebones Debian web hosting server + Palworld game server. Also hosts CI/CD pipeline (self-hosted GitHub Actions runner). |
| Notes | Will PXE boot from R730 (diskless). SSD goes to jumpbox. Services need migrating before it can join the cluster. |

## External Infrastructure

### proxy-vps (Hetzner VPS)

| Spec | Value |
|------|-------|
| Provider | Hetzner Cloud |
| OS | Linux (Debian-based) |
| SSH | Port 2222 |
| Current role | Caddy reverse proxy — routes internet traffic through NetBird VPN to K8s cluster ingress. Handles TLS via Cloudflare DNS-01. Also does UDP port forwarding (Palworld on port 8211 → deb-web). |
| Domains | *.bearflinn.com (wildcard to K8s), pennydreadfulsfx.com, gin-house.bearflinn.com (Home Assistant), ph.bearflinn.com (PostHog proxy) |

---

## New Hardware (To Be Incorporated)

### Servers

#### Dell PowerEdge R730xd

| Spec | Value |
|------|-------|
| Model | Dell PowerEdge R730xd (extended storage chassis) |
| Form factor | 2U rackmount |
| CPU | 1× Intel Xeon E5-2630 v3 — 8C/16T @ 2.4 GHz (turbo), 20 MB cache, 85W TDP. Second socket empty. |
| RAM | 32 GB DDR4 ECC (expandable — 24 DIMM slots total) |
| NIC | Broadcom GbE 4-port 5720-t rNDC (onboard) |
| Drive bays | **12× 3.5" front** (hot-swap, 2 backplanes) + **2× 2.5" rear** — confirmed |
| RAID | Dell PERC H730 Mini |
| PSUs | 2× 750W redundant (Delta) |
| iDRAC | `<r730xd_idrac_ip>`, firmware 2.86.86.86, IPMI + SSH racadm working |
| Service tag | 45L1DH2 |
| Built | December 2016 |
| GPU | TBD (supports full-height PCIe cards) |
| OS | Debian 13.4 (Trixie), kernel 6.12.74, UEFI boot |
| OS IP | `<r730xd_ip>` on eno1 (static) |
| Boot drive | Samsung SSD 850 EVO 250GB in bay 12 (rear 2.5" slot), non-RAID mode |
| Status | **Online.** OS installed 2026-03-26 via preseeded USB. Baseline playbook applied. |
| Storage | MergerFS pool: 5×3TB data + 2×4TB parity (SnapRAID). 15TB usable. Deployed via `r730xd-storage.yml`. |
| TODO | Set up NFS exports, bcache SSD acceleration, enroll in NetBird |

#### Quanta QSSC-2ML

| Spec | Value |
|------|-------|
| Model | Quanta QSSC-2ML |
| Form factor | Rackmount |
| CPU | 2× Intel Xeon E5-2670 0 — 8C/16T @ 2.6 GHz (turbo 3.3 GHz), Sandy Bridge-EP, 115W TDP each (230W total CPU) |
| RAM | 64 GB DDR3 1333 MHz |
| Storage | 6× SATA ports, no hot-swap bays — drives mount internally. 240 GB SSD installed as boot drive. |
| GPU | TBD — check PCIe slots |
| Remote mgmt | IPMI/BMC at `<quanta_bmc_ip>` (on lab subnet) |
| BIOS | AMI v2.14.1219 (dated 2012-10-04), UEFI boot supported |
| Network | 4-port NIC via PCIe riser (installed 2026-03-27) |
| Status | 240 GB boot drive installed, OS imaging via preseeded ISO |
| TODO | Set BMC/IPMI static IP, check PCIe slot count/type |

### Network Equipment

#### Aerohive AP130 (×2)

| Spec | Value |
|------|-------|
| Model | Aerohive AP130 (×2) |
| Type | Wireless access point |
| WiFi | 802.11ac Wave 1, dual-band |
| PoE | Yes (802.3at from SR2024) |
| Firmware | #1: HiveOS 6.5r8b (Oct 2017), #2: HiveOS 6.5r1b (Jul 2015) |
| MAC (mgt0) | #1: 88:5b:dd:b6:14:c0, #2: 88:5b:dd:2d:22:80 |
| Hostname | #1: AH-b614c0, #2: AH-2d2280 |
| Status | Factory reset, standalone mode confirmed, CAPWAP disabled |
| Notes | #2 has older firmware and 1 bad NAND block — consider updating to match #1 |

#### Aerohive AP230

| Spec | Value |
|------|-------|
| Model | Aerohive AP230 |
| Type | Wireless access point |
| WiFi | 802.11ac Wave 1, dual-band, 3×3:3 MIMO |
| PoE | Yes (802.3at from SR2024) |
| Firmware | HiveOS 8.1r1 (Aug 2017) |
| MAC (mgt0) | 9c:5d:12:1c:ea:80 |
| Hostname | AH-1cea80 |
| Status | Factory reset, standalone mode confirmed, CAPWAP disabled |
| Notes | Higher-end model — primary AP. 1 GHz CPU, Linux 3.16.36 |

#### Aerohive SR2024 Switch

| Spec | Value |
|------|-------|
| Model | Aerohive SR2024 |
| Type | Managed gigabit switch |
| Ports | 24× 1GbE + 2× SFP (+ 2× combo GbE/SFP) |
| PoE | Yes — 802.3at (PoE+), confirmed powering all 3 APs |
| Firmware | HiveOS 6.5r8 (Aug 2017) |
| MAC (mgt0) | 08:ea:44:86:4d:00 |
| Hostname | AH-864d00 |
| Status | Factory reset, standalone mode confirmed, CAPWAP disabled |
| Management | SSH + CLI (web UI exists but read-only). No cloud dependency. |
| Features confirmed | 802.1Q VLANs, LACP link aggregation, trunk/access port modes |

### Spare GPUs

| GPU | VRAM | PCIe | Notes |
|-----|------|------|-------|
| NVIDIA GTX 1080 Ti | 11 GB | x16 Gen3 | Best GPU in the fleet — strong for inference workloads |
| NVIDIA GTX 1050 Ti | 4 GB | x16 Gen3 | Low power (~75W, no external power connector on most models) |
| NVIDIA GTX 760 | 2 GB | x16 Gen3 | Oldest card, limited utility — basic display/compute only |

### Hard Drives (All Installed in R730xd)

| Drives | Capacity | Type | Role | R730xd Bays |
|--------|----------|------|------|-------------|
| 2× 4 TB | 8 TB total | HDD | SnapRAID parity | Bays 0, 3 |
| 5× 3 TB | 15 TB total | HDD | MergerFS data pool | Bays 1, 2, 4, 5, 8 |
| **Total installed** | **23 TB raw (15 TB usable)** | | | |

Note: 1× 4TB was dead on arrival and discarded. Bay 8 drive had existing data, mounted directly into pool.

---

## Machines Being Removed from Cluster

### msi-laptop → Dev Machine

- Workloads to migrate: monitoring/observability (Prometheus, Grafana, Loki — planned but may not be deployed yet)
- GPU (GTX 1060 3GB) stays with the laptop
- Will no longer be in K8s inventory after migration

---

## Aggregate Resources — Current Active Cluster

| Resource | Total |
|----------|-------|
| CPU cores | 10 (20 threads) |
| RAM | 64 GB |
| GPUs | 2× GTX 1060 3GB |
| Storage | ~8.7 TB raw |
| Nodes | 1 control plane + 2 workers |

## Aggregate Resources — All Available Hardware (Post-Migration Potential)

| Resource | Estimate |
|----------|----------|
| CPU cores | ~30C/52T (Inspiron 2C/4T + Optiplex 4C/4T + R730 8C/16T + Quanta 16C/32T) — tower PC excluded (standalone GPU workstation) |
| RAM | ~136 GB (8 + 32 + 32 + 64) — tower PC (24 GB) excluded |
| GPUs | 1080 Ti (11GB), 1060 3GB (tower), 1050 Ti (4GB), 760 (2GB) |
| Storage (installed) | ~9.2 TB raw |
| Storage (spare HDDs) | ~23 TB raw (2×4TB + 5×3TB, 1×3TB has data pending backup) |
| Network | 24-port managed GbE switch, 3× WiFi APs |
| Physical machines | 5 (Inspiron, Optiplex, R730, Quanta, Tower PC) — MSI laptop removed from cluster |

---

## Previously Unlisted Hardware

### Mini PC (Current NAS / Future Jumpbox)

| Spec | Value |
|------|-------|
| Model | TBD |
| Form factor | Mini PC |
| CPU | AMD C60 APU — 2C/2T @ 1.0 GHz (1.33 boost), Bobcat x86-64 |
| RAM | 4 GB |
| Storage | Currently holds the 3 TB drive with important data |
| NIC (current) | Onboard (assumed 1 port) |
| NIC (to add) | Spare 4-port NIC |
| Current role | NAS |
| Planned role | Dedicated jumpbox |
| Notes | Full motherboard. 3TB drive data must be backed up before repurposing. Will receive an SSD (from Optiplex or Inspiron) to improve I/O for Claude Code and terminal workflows. |

### APC Back-UPS RS 1500

| Spec | Value |
|------|-------|
| Model | APC Back-UPS RS 1500 |
| Capacity | 1500 VA / 865 W |
| Output | Simulated sine wave (stepped approximation) |
| Data port | RJ45 (APC proprietary — NOT Ethernet. Needs APC RJ45-to-USB cable, e.g., 940-0127) |
| Monitoring | NUT (Network UPS Tools) via the APC cable to a connected machine |
| Compatibility | **R730 will NOT boot on simulated sine wave.** Server PSUs require pure sine. Quanta likely same issue — check before connecting. |
| Notes | Use for machines with consumer PSUs only: Inspiron, Optiplex, Tower PC, switch. Do NOT put servers on this UPS. |

### Spare 4-Port NIC

- **Installed in the Quanta** via PCIe riser (2026-03-27).

## Open Questions / TODO

- [x] ~~Identify the CPU in the R730~~ — **Intel Xeon E5-2630 v3 (8C/16T @ 2.4 GHz)**
- [x] ~~Identify both CPUs in the Quanta QSSC-2ML~~ — **2× Intel Xeon E5-2670 (8C/16T each)**
- [x] ~~Check R730 drive bay configuration~~ — **12× 3.5" front (LFF) + 2× 2.5" rear**
- [x] ~~Check Quanta drive bay configuration~~ — **6× SATA, internal mount, no hot-swap**
- [x] ~~Test POST on both servers~~ — **both confirmed**
- [x] ~~Verify iDRAC (R730) and BMC/IPMI (Quanta) remote management access~~ — **iDRAC SSH racadm working (no Enterprise license — no virtual media). Quanta BMC/IPMI at `<quanta_bmc_ip>`.**
- [x] ~~Test all 24 ports on the SR2024 switch~~ — **ports 1–4 confirmed working (APs on 1–3, laptop on 4). Full port test pending but switch responds correctly. VLANs, LACP, PoE all confirmed (2026-03-27).**
- [x] ~~Determine Aerohive AP firmware situation~~ — **all 3 APs run standalone via `no capwap client enable`. Factory reset and CAPWAP disabled on all devices (2026-03-27). See docs/aerohive-serial-interface.md for details.**
- [x] ~~Back up the data on the one 3 TB drive~~ — **mounted directly into R730xd MergerFS pool (bay 8), data preserved in-place**
- [x] ~~Determine which spare HDDs go into which machines~~ — **All data HDDs go in R730xd (MergerFS pool). SSDs: 1 → jumpbox, 1 → tower PC (LLM storage), 1 → R730 bcache**
- [ ] Determine GPU placement across machines
- [ ] Plan power and rack/shelf layout for the new room
- [ ] Assess power draw — servers can pull 500W+ each under load
- [ ] Assess noise — R730 and Quanta will be loud under load
