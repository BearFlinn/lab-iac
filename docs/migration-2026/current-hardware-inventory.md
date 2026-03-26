# Current Hardware Inventory

Last updated: 2026-03-24

---

## Active K8s Cluster Nodes

### dell-inspiron-15 — Control Plane

| Spec | Value |
|------|-------|
| Model | Dell Inspiron 15-3567 |
| Form factor | Laptop |
| CPU | Intel i3-7100U — 2C/4T @ 2.7 GHz |
| RAM | 8 GB |
| Storage | 256 GB SSD |
| GPU | None |
| Network | enp2s0, IP 10.0.0.226 |
| Current role | K8s control plane (single-node etcd, apiserver, scheduler, controller-manager) |

### tower-pc — Worker

| Spec | Value |
|------|-------|
| Model | Custom full tower |
| Form factor | Full tower |
| CPU | Intel i7-4790 — 4C/8T @ 3.6–4.0 GHz |
| RAM | 24 GB |
| Storage | 128 GB NVMe (bcache backing), 240 GB SATA SSD (OS), 1 TB HDD (NFS), 3×2 TB HDD (ZFS RAID-Z1 ~4 TB usable) — **~6.4 TB total raw** |
| GPU | NVIDIA GTX 1060 3 GB |
| Network | eno1, IP 10.0.0.249 |
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
| Network | enp61s0, IP 10.0.0.177 |
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
| Storage | 512 GB SSD |
| GPU | None |
| Network | IP not currently assigned in cluster |
| Current role | **Not in K8s cluster.** Currently runs as `deb-web` — barebones Debian web hosting server + Palworld game server. Also hosts CI/CD pipeline (self-hosted GitHub Actions runner). |
| Notes | Was planned as general-compute K8s worker. Services need migrating before it can join the cluster. |

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
| NIC | 4-port (onboard) |
| Drive bays | **12× 3.5" front** (hot-swap) + **2× 2.5" rear** — confirmed |
| GPU | TBD (supports full-height PCIe cards) |
| Status | Decommissioned, needs assessment |
| TODO | Test POST, check iDRAC access, verify drive bay count/config, check which bays are populated |

#### Quanta QSSC-2ML

| Spec | Value |
|------|-------|
| Model | Quanta QSSC-2ML |
| Form factor | Rackmount |
| CPU | 2× Intel Xeon E5-2670 0 — 8C/16T @ 2.6 GHz (turbo 3.3 GHz), Sandy Bridge-EP, 115W TDP each (230W total CPU) |
| RAM | 64 GB DDR3 1333 MHz |
| Storage | 6× SATA ports, no hot-swap bays — drives mount internally. Currently empty. |
| GPU | TBD — check PCIe slots |
| Remote mgmt | IPMI/BMC supported — set static IP while monitor is connected |
| BIOS | AMI v2.14.1219 (dated 2012-10-04) |
| Status | POST confirmed, no drives installed |
| TODO | Set BMC/IPMI static IP, check PCIe slot count/type, install OS drive |

### Network Equipment

#### Aerohive AP130 (×2)

| Spec | Value |
|------|-------|
| Model | Aerohive AP130 |
| Type | Wireless access point |
| WiFi | 802.11ac Wave 1, dual-band |
| PoE | Yes (802.3af) |
| Status | Need to verify firmware/standalone mode capability |
| TODO | Check if running HiveOS or can be flashed to standalone. Aerohive was acquired by Extreme Networks — may need community firmware. |

#### Aerohive AP230

| Spec | Value |
|------|-------|
| Model | Aerohive AP230 |
| Type | Wireless access point |
| WiFi | 802.11ac Wave 1, dual-band, 3×3:3 MIMO |
| PoE | Yes (802.3af) |
| Status | Need to verify firmware/standalone mode capability |
| TODO | Same firmware considerations as AP130s. Higher-end model — better for primary AP. |

#### Aerohive SR2024 Switch

| Spec | Value |
|------|-------|
| Model | Aerohive SR2024 |
| Type | Managed gigabit switch |
| Ports | 24× 1GbE (12× PoE) |
| PoE | Yes — 12 ports |
| Status | Needs testing |
| Notes | Same Aerohive ecosystem as the APs — may share management/firmware considerations |
| TODO | Test all ports, check management interface, verify VLAN support, reset to factory if needed |

### Spare GPUs

| GPU | VRAM | PCIe | Notes |
|-----|------|------|-------|
| NVIDIA GTX 1080 Ti | 11 GB | x16 Gen3 | Best GPU in the fleet — strong for inference workloads |
| NVIDIA GTX 1050 Ti | 4 GB | x16 Gen3 | Low power (~75W, no external power connector on most models) |
| NVIDIA GTX 760 | 2 GB | x16 Gen3 | Oldest card, limited utility — basic display/compute only |

### Spare Hard Drives

| Drives | Capacity | Type | Notes |
|--------|----------|------|-------|
| 3× 4 TB | 12 TB total | HDD | Available for storage pool |
| 5× 3 TB | 15 TB total | HDD | **1 drive has data that needs to be preserved before reuse** |
| **Total spare** | **27 TB raw** | | |

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

These numbers are approximate until server CPUs are identified.

| Resource | Estimate |
|----------|----------|
| CPU cores | TBD (depends on server CPUs — likely 20-40+ cores total) |
| RAM | ~152 GB (8 + 24 + 32 + 32 + 64 − 32 MSI removal) |
| GPUs | 1080 Ti (11GB), 1060 3GB (tower), 1050 Ti (4GB), 760 (2GB) |
| Storage (installed) | ~9.2 TB raw |
| Storage (spare HDDs) | ~27 TB raw |
| Network | 24-port managed GbE switch, 3× WiFi APs |
| Physical machines | 4 (inspiron, tower, optiplex, R730, Quanta) — 5 total minus MSI |

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
| Notes | Full motherboard. 3TB drive data must be backed up before repurposing. |

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

- **Going into the Quanta** — Quanta has no onboard RJ45 (currently using RJ45-to-SFP adapter). Needs a PCIe riser to install.

## Open Questions / TODO

- [ ] Identify the CPU in the R730 (check iDRAC or boot to BIOS)
- [ ] Identify both CPUs in the Quanta QSSC-2ML (check BMC/IPMI or boot to BIOS)
- [ ] Check R730 drive bay configuration (SFF vs LFF)
- [ ] Check Quanta drive bay configuration
- [ ] Test POST on both servers
- [ ] Verify iDRAC (R730) and BMC/IPMI (Quanta) remote management access
- [ ] Test all 24 ports on the SR2024 switch
- [ ] Determine Aerohive AP firmware situation — can they run standalone without HiveManager/cloud?
- [ ] Back up the data on the one 3 TB drive before repurposing
- [ ] Determine which spare HDDs go into which machines
- [ ] Determine GPU placement across machines
- [ ] Plan power and rack/shelf layout for the new room
- [ ] Assess power draw — servers can pull 500W+ each under load
- [ ] Assess noise — R730 and Quanta will be loud under load
