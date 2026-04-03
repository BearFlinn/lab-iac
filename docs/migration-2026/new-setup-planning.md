# New Setup Planning

Last updated: 2026-04-03

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
                      NetBird VPN
                            |
          +-----------------+------------------+
          |                 |                  |
          v                 v                  v
+------------------+ +-------------+ +------------------+
| Quanta QSSC-2ML | | Optiplex    | | Dell Inspiron 15 |
| K8s Worker       | | K8s Worker  | | K8s Control Plane|
| 32C / 64GB       | | 4C / 32GB   | | 2C / 8GB         |
+------------------+ +-------------+ +------------------+

+------------------+ +------------------+
| Dell R730        | | Tower PC         |
| Storage + VMs    | | Router + GPU     |
| Standalone       | | Standalone       |
+------------------+ +------------------+
```

## Decided Role Assignments

### Dell PowerEdge R730xd → Storage Backbone + Occasional VMs (Standalone)

- **Role:** Dedicated storage server + light VM host (Proxmox or bare Linux)
- **CPU:** Xeon E5-2630 v3 (8C/16T @ 2.4 GHz) — plenty for NFS + ZFS + VMs
- **Why:** Up to 12× 3.5" front hot-swap bays + 2× 2.5" rear + 4-port NIC + iDRAC. Purpose-built for this role.
- **Replaces:** tower-pc as storage backbone
- **Storage plan:**
  - Spare drives: 2×4TB + 4×3TB = 20TB raw (plus 1×3TB with data pending backup)
  - Potentially migrate tower-pc's 3×2TB ZFS drives = +6TB raw
  - Total available: up to **27TB raw** (29TB once 3TB drive data is backed up) — fits easily in the R730xd's bays with room to spare
  - 2× 2.5" rear bays ideal for OS/boot SSDs (keep spinning rust for data only)
- **VMs:**
  - **Staging VM (migration):** Hosts critical workloads (web services, etc.) while the K8s cluster is being rebuilt. Ensures no downtime for production services during the transition. Torn down once the new cluster is online.
  - Long-term: occasional, light use — cybersec experimentation, provisioning hardware for friends, etc. Spin up when needed, shut down when not.
- **Storage software:** MergerFS + SnapRAID — chosen for mismatched drive support without licensing cost
- **Boot cache:** One SSD as bcache for the data pool
- **Storage status:** MergerFS pool operational (5×3TB data + 2×4TB parity). SnapRAID configured. Deployed via `r730xd-storage.yml`.
- **Open questions:**
  - NFS? S3 (Garage/MinIO)? Both?
  - bcache SSD for read acceleration (deferred)

### Quanta QSSC-2ML → Primary K8s Worker

- **Role:** Main K8s compute workhorse — 2× CPUs, 32 cores, 64 GB RAM, fully dedicated to cluster
- **Why:** Most powerful machine in the fleet. K8s benefits from strong workers, and this gives headroom for automation/parallel workloads.
- **No VMs** — Quanta is fully committed to K8s
- **Boot:** PXE boot from R730 (diskless)
- **Network:** 4-port NIC installed via PCIe riser. 1-2 ports direct-connected to R730 for dedicated NFS I/O, remaining ports on switch

### Dell Optiplex 9020 → K8s Worker

- **Role:** Second K8s worker node
- **Migrating from:** Standalone deb-web duties (web hosting, Palworld, CI/CD runner) — these move into K8s workloads
- **Specs:** i7-4790 4C/8T, 32 GB RAM
- **Boot:** PXE boot from R730 (diskless) — SSD repurposed elsewhere

### Dell Inspiron 15 → K8s Control Plane (Unchanged)

- **Role:** Stays as K8s control plane
- **Why:** Lightweight enough for a small cluster's control plane. Not worth the effort of migrating this role to another machine.
- **Specs:** i3-7100U 2C/4T, 8 GB RAM
- **Boot:** PXE boot from R730 (diskless) — SSD repurposed to jumpbox

### Tower PC → Router + GPU Inference Workstation (Standalone)

- **Role:** Lab router + GPU inference workstation, removed from K8s cluster
- **Why router here:** CPU will be largely unused by inference workloads, it's already outside the cluster, and its other workloads are non-critical. Consolidates routing onto an existing machine rather than dedicating hardware.
- **GPU plan:** 1080 Ti (11GB) + existing 1060 (3GB) + 1050 Ti (4GB) = 18 GB combined VRAM
  - GTX 760 (2GB) — probably not worth a slot
  - Need to verify PSU wattage and available PCIe slots/power connectors
- **Storage:** Existing drives stay (240GB OS SSD, etc). ZFS pool drives may migrate to R730. Adding an SSD for LLM model storage.
- **Software:** Ollama / vLLM / text-generation-inference TBD. Likely exposed as API to other machines.

### MSI Laptop → Dev Machine (Removed from Cluster)

- **Role:** Personal development workstation
- **No cluster role.** GPU (GTX 1060 3GB) stays with the laptop.

### Mini PC (AMD C60) → Jumpbox / Command Center

- **Role:** Dedicated jumpbox — SSH gateway, Claude Code, stats display
- **Storage:** Receives an SSD from Optiplex or Inspiron (replacing the 3TB HDD after data backup)
- **Why:** AMD C60 is too slow for routing but fine for terminal/SSH work. SSD removes disk I/O as bottleneck.

### proxy-vps (Hetzner) → Stays As-Is

- Caddy reverse proxy + NetBird VPN gateway
- Role unchanged

## Boot & Storage Strategy

**K8s nodes are diskless.** Inspiron, Optiplex, and Quanta all PXE boot from the R730. This makes them disposable — any node can be rebuilt by just PXE booting a replacement. The R730 runs the PXE/TFTP server.

**SSD redistribution:**

| SSD | Source | Destination | Purpose |
|-----|--------|-------------|---------|
| 256 GB | Inspiron | Jumpbox | OS + Claude Code I/O |
| 512 GB | Optiplex | Tower PC | LLM model storage |
| 128 GB NVMe | Tower PC | R730 | bcache for MergerFS pool |

**Stateful workloads run on R730**, not in K8s. K8s is purely stateless — NFS PVCs for anything that needs persistence, served from R730's MergerFS pool.

**Quanta gets dedicated NFS link(s)** — 1-2 direct connections to R730 bypassing the switch to avoid I/O bottlenecks on the heaviest worker.

## Network Equipment

### SR2024 Switch

- 24-port managed GbE — backbone for the new room
- All machines connect through this
- VLAN capability if needed for segmentation

### Aerohive APs (2× AP130, 1× AP230, 1× AP630)

- AP630 as primary (highest performance: 4×4:4 MU-MIMO, 802.11ac Wave 2). Restored to stock HiveOS IQ Engine 10.6r7 on 2026-04-03 after Debian router project was closed out ([ADR-011](../decisions/011-ap630-restored-to-stock-wifi-ap.md)).
- AP230 as secondary (3×3:3 MIMO)
- AP130s for coverage extension
- Standalone mode confirmed — all 4 run HiveOS CLI without cloud/controller dependency

## Network Topology

**Status: NEEDS DISCUSSION** — current network setup is acknowledged as messy. Need to define:

- [ ] Current network layout (what's the mess?)
- [ ] Target network topology for the new room
- [ ] VLAN segmentation? (e.g., storage VLAN on R730's 4-port NIC, management VLAN, K8s VLAN)
- [ ] DNS strategy (local DNS? Pi-hole? CoreDNS outside the cluster?)
- [ ] How NetBird VPN fits into the new topology
- [ ] WiFi architecture (AP placement, SSIDs, VLANs)
- [ ] IP addressing scheme for the new setup

---

## K8s Cluster Summary (Post-Migration)

| Resource | Total |
|----------|-------|
| Control plane nodes | 1 (Inspiron) |
| Worker nodes | 2 (Quanta + Optiplex) |
| CPU cores (workers) | 36 (32 + 4) |
| CPU threads (workers) | ~68 (depends on Quanta CPUs) |
| RAM (workers) | 96 GB (64 + 32) |
| RAM (control plane) | 8 GB |

Compared to current cluster: more than 3× the compute cores, 50% more RAM, on fewer but much stronger machines.

---

## Open Decisions

- [x] ~~K8s vs alternatives~~ — **keeping K8s**
- [x] ~~Quanta role~~ — **dedicated K8s worker**
- [x] ~~Dell Inspiron fate~~ — **stays as control plane**
- [x] ~~Optiplex role~~ — **K8s worker**
- [x] ~~Tower-pc role~~ — **standalone GPU inference**
- [x] ~~R730 role~~ — **storage + occasional VMs**
- [x] ~~VM host~~ — **R730**
- [ ] **Network topology** — needs full discussion
- [ ] **Tower-pc PSU/PCIe audit** — can it actually hold 3 GPUs?
- [x] ~~R730 storage software~~ — **MergerFS + SnapRAID** (mismatched drives, no license cost)
- [x] ~~R730 drive layout~~ — **2×4TB parity (bays 0+3), 5×3TB data (bays 1+2+4+5+8). See `ansible/inventory/r730xd.yml`.**
- [x] ~~3TB data backup~~ — **drive mounted directly into MergerFS pool (bay 8), data preserved in-place**
- [x] ~~R730 CPU identification~~ — **Xeon E5-2630 v3, 8C/16T**
- [ ] **Quanta CPU identification** — check BMC/IPMI/BIOS
- [ ] **Power assessment** — R730 + Quanta + tower with 3 GPUs could pull 1kW+ combined
- [ ] **UPS strategy** — APC RS 1500 (865W, simulated sine). R730 and Quanta (likely) won't run on it. Use for: Inspiron, Optiplex, Tower PC, switch. NUT for graceful shutdown of servers via IPMI/iDRAC when power drops.
- [ ] **UPS data cable** — need APC RJ45-to-USB cable (e.g., 940-0127) to connect to a monitoring machine. Check if one came with the unit.
- [ ] **Quanta sine wave tolerance** — verify whether Quanta PSU accepts simulated sine or requires pure sine like the R730
- [ ] **Migration order and steps** — blocked on network decisions
