# New Setup Planning

Last updated: 2026-03-24

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
| Storage + VMs    | | GPU Inference    |
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
  - Spare drives: 3×4TB + 5×3TB = 27TB raw
  - Potentially migrate tower-pc's 3×2TB ZFS drives = +6TB raw
  - Total available: up to **33TB raw** — fits easily in the R730xd's bays with room to spare
  - 2× 2.5" rear bays ideal for OS/boot SSDs (keep spinning rust for data only)
- **VMs:** Occasional, light use — cybersec experimentation, provisioning hardware for friends, etc. Spin up when needed, shut down when not.
- **Open questions:**
  - ZFS? MergerFS + SnapRAID? TrueNAS? Proxmox w/ ZFS?
  - RAID level: Z2 recommended with this many drives (double parity)
  - NFS? S3 (Garage/MinIO)? Both?
  - Back up the 3TB drive with important data first

### Quanta QSSC-2ML → Primary K8s Worker

- **Role:** Main K8s compute workhorse — 2× CPUs, 32 cores, 64 GB RAM, fully dedicated to cluster
- **Why:** Most powerful machine in the fleet. K8s benefits from strong workers, and this gives headroom for automation/parallel workloads.
- **No VMs** — Quanta is fully committed to K8s

### Dell Optiplex 9020 → K8s Worker

- **Role:** Second K8s worker node
- **Migrating from:** Standalone deb-web duties (web hosting, Palworld, CI/CD runner) — these move into K8s workloads
- **Specs:** i7-4790 4C/8T, 32 GB RAM, 512 GB SSD

### Dell Inspiron 15 → K8s Control Plane (Unchanged)

- **Role:** Stays as K8s control plane
- **Why:** Lightweight enough for a small cluster's control plane. Not worth the effort of migrating this role to another machine.
- **Specs:** i3-7100U 2C/4T, 8 GB RAM, 256 GB SSD

### Tower PC → Dedicated GPU Inference Workstation (Standalone)

- **Role:** GPU inference workstation, removed from K8s cluster
- **GPU plan:** 1080 Ti (11GB) + existing 1060 (3GB) + 1050 Ti (4GB) = 18 GB combined VRAM
  - GTX 760 (2GB) — probably not worth a slot
  - Need to verify PSU wattage and available PCIe slots/power connectors
- **Storage:** Existing drives stay (240GB OS SSD, etc). ZFS pool drives may migrate to R730.
- **Software:** Ollama / vLLM / text-generation-inference TBD. Likely exposed as API to other machines.

### MSI Laptop → Dev Machine (Removed from Cluster)

- **Role:** Personal development workstation
- **No cluster role.** GPU (GTX 1060 3GB) stays with the laptop.

### proxy-vps (Hetzner) → Stays As-Is

- Caddy reverse proxy + NetBird VPN gateway
- Role unchanged

## Network Equipment

### SR2024 Switch

- 24-port managed GbE — backbone for the new room
- All machines connect through this
- VLAN capability if needed for segmentation

### Aerohive APs (2× AP130, 1× AP230)

- AP230 as primary (higher performance, 3×3:3 MIMO)
- AP130s for coverage extension
- Firmware situation needs resolving (standalone vs cloud-managed)

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
- [ ] **R730 storage software** — ZFS vs TrueNAS vs Proxmox w/ ZFS vs MergerFS+SnapRAID
- [ ] **R730 drive layout** — which drives go where
- [ ] **3TB data backup** — must happen before any drive reformatting
- [x] ~~R730 CPU identification~~ — **Xeon E5-2630 v3, 8C/16T**
- [ ] **Quanta CPU identification** — check BMC/IPMI/BIOS
- [ ] **Power assessment** — R730 + Quanta + tower with 3 GPUs could pull 1kW+ combined
- [ ] **UPS strategy** — APC RS 1500 (865W, simulated sine). R730 and Quanta (likely) won't run on it. Use for: Inspiron, Optiplex, Tower PC, switch. NUT for graceful shutdown of servers via IPMI/iDRAC when power drops.
- [ ] **UPS data cable** — need APC RJ45-to-USB cable (e.g., 940-0127) to connect to a monitoring machine. Check if one came with the unit.
- [ ] **Quanta sine wave tolerance** — verify whether Quanta PSU accepts simulated sine or requires pure sine like the R730
- [ ] **Migration order and steps** — blocked on network decisions
