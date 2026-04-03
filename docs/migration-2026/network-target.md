# Target Network Architecture

Last updated: 2026-04-03

## Physical Layout

Everything lab-related goes in the **dedicated closet**. Full ability to run new cable anywhere in the house.

```
Closet (Lab):
  - SR2024 switch (24-port managed)
  - Dell PowerEdge R730 (storage + VMs)
  - Quanta QSSC-2ML (K8s worker)
  - Dell Optiplex 9020 (K8s worker)
  - Dell Inspiron 15 (K8s control plane)
  - Tower PC (router + GPU inference) — may be in closet or nearby depending on noise/heat

Cable runs from closet:
  - To Xfinity gateway (uplink)
  - To master bedroom (sibling's drop)
  - To garage/workshop
  - To wherever WiFi APs are placed
```

## Network Topology

```
              [ISP / Xfinity Gateway]
                 Bridge mode
                  Living Room
                        |
                        | (cable run to closet)
                        v
              +-------------------+
              |    Tower PC       |
              |  Router + GPU     |
              |  NAT/DHCP/DNS/FW  |
              +-------------------+
                        |
                        v
            +-------------------+
            |    SR2024 Switch  |
            |  24-port managed  |
            |    VLAN-capable   |
            +-------------------+
              |  |  |  |  |  |  |  |  |
              v  v  v  v  v  v  v  v  v
           Lab machines    Bedroom   Garage   APs
           (VLAN 10)      (VLAN 1)  (VLAN 1) (trunk)
```

### How This Works

- **Xfinity gateway in bridge mode** — passes the public IP through to the Tower PC, which handles all routing
- **Tower PC is the router** — runs NAT, DHCP, DNS, and inter-VLAN firewall rules. CPU is largely unused by its GPU inference workload, and its other roles are non-critical, making it a good fit.
- **SR2024 handles VLANs** — lab traffic is segmented at Layer 2, with the Tower PC providing inter-VLAN routing and firewall rules (router-on-a-stick)
- **Lab machines use static IPs** (as they already do via Ansible) on the lab VLAN
- **Home devices get DHCP from the Tower PC** on the default/untagged VLAN
- **Lab VLAN is isolated from home VLAN** — inter-VLAN traffic goes through the Tower PC's firewall rules

### What This Unlocks (vs. Xfinity-only)

- **Inter-VLAN firewall rules** — granular control over what can cross VLAN boundaries
- **Custom DHCP per VLAN** — static assignments for lab, dynamic for home
- **Local DNS** — lab-internal resolution (e.g., `r730.lab.local`) without /etc/hosts hacks
- **Full control** — no dependency on Xfinity gateway's limited feature set

## VLAN Design

With the Tower PC as router, full inter-VLAN routing and firewall rules are available. Start with 2 VLANs, expand as needed.

| VLAN | ID | Purpose | Members |
|------|----|---------|---------|
| Default (Home) | 1 (untagged) | Home network — Xfinity DHCP, personal devices, internet access | Xfinity uplink, bedroom drop, garage drop, WiFi APs (home SSID), lab machines (default gateway) |
| Lab | 10 (tagged) | Lab-internal traffic — K8s, storage, inference | Inspiron, Quanta, Optiplex, R730, Tower PC |

### How Lab Machines Handle Two VLANs

Each lab machine gets:
- **Untagged port on VLAN 1** for internet access (default gateway via Xfinity)
- **Tagged VLAN 10** on the same port (802.1Q trunk) for lab-internal traffic

This means lab machines have two IPs — one on the home subnet (for internet) and one on the lab subnet (for inter-machine communication). Kubernetes, NFS, and all lab traffic uses the VLAN 10 addresses. Internet-bound traffic goes through VLAN 1.

Alternatively, keep it even simpler: **just use VLAN 10 as a dedicated storage network** and leave everything else on VLAN 1. The R730's 4-port NIC makes this easy — one port on VLAN 1 (general), one or more ports on VLAN 10 (storage only).

### Optional: Storage Sub-VLAN

| VLAN | ID | Purpose | Members |
|------|----|---------|---------|
| Storage | 20 | NFS/S3 traffic only | R730 (dedicated NIC port), Quanta, Optiplex, Inspiron |

This is the highest-value segmentation — keeps storage I/O off the general network. The R730's 4-port NIC can dedicate ports to this. Worth doing even without a router.

**Quanta direct link:** The Quanta will have 1-2 ports direct-connected to the R730 (bypassing the switch entirely) for dedicated NFS I/O. As the heaviest K8s worker, this prevents it from saturating the switch with storage traffic. Remaining Quanta NIC ports connect to the switch for general/K8s traffic.

## WiFi Architecture

| AP | Location | Notes |
|----|----------|-------|
| AP630 (primary) | Central location — living room or hallway | Highest performance (4×4:4 MU-MIMO, 802.11ac Wave 2). Restored to stock HiveOS 2026-04-03 ([ADR-011](../decisions/011-ap630-restored-to-stock-wifi-ap.md)). |
| AP230 (secondary) | Second coverage zone | Strong performance (3×3:3 MIMO) |
| AP130 #1 | Garage/workshop | Workshop coverage |
| AP130 #2 | Far side of house or closet area | Dead spot coverage |

- With the Tower PC as router, VLAN-tagged SSIDs (e.g., separate guest network) are fully supported — the router can provide DHCP and firewall rules per VLAN.
- Xfinity WiFi can be **disabled** once AP coverage is verified, or left on as a fallback.
- **PoE note:** SR2024 provides PoE (802.3at/PoE+) — no injectors needed.

## NetBird VPN

Unchanged from current setup:
- NetBird continues to provide external access to the lab via the Hetzner VPS
- NetBird client runs on machines that need external reachability (K8s nodes, R730)
- Caddy on VPS still routes to K8s ingress via NetBird
- Peer-to-peer — doesn't depend on the local router

## DNS

- **For now:** Continue using /etc/hosts managed by Ansible (current approach) during migration
- **Post-migration:** Run DNS on the Tower PC (router) for whole-network resolution — lab-internal names (e.g., `r730.lab.local`, `quanta.lab.local`) and upstream forwarding. Eliminates the need for /etc/hosts management via Ansible.
- **Alternative:** Run CoreDNS or Pi-hole on K8s if preferred, but having it on the router is simpler and doesn't create a chicken-and-egg problem with K8s needing DNS to boot.

## Cable Runs Needed

| From | To | Purpose |
|------|----|---------|
| Xfinity gateway (living room) | Closet | Uplink to SR2024 |
| Closet (SR2024) | Master bedroom | Sibling's connection |
| Closet (SR2024) | Garage | Workshop connection |
| Closet (SR2024) | AP locations (×3) | WiFi APs (PoE from switch, no injectors needed) |
| Within closet | Short patch cables | All lab machines to SR2024 |

## Open Questions

- [x] **SR2024 VLAN verification** — confirmed: supports 802.1Q VLAN tagging, LACP bonding, trunk/access port modes
- [x] **SR2024 PoE** — confirmed: SR2024 provides PoE (802.3at/PoE+). All 3 APs powered successfully by the switch. No injectors needed.
- [x] **Aerohive firmware** — confirmed: standalone mode works via `no capwap client enable`. VLAN-tagged SSIDs work via user-profile attributes. Switch runs HiveOS 6.5r8, AP230 runs HiveOS 8.1r1.
- [ ] **Xfinity gateway model** — does it play nice with a managed switch doing VLANs on the LAN side?
- [ ] **Storage VLAN worth it now?** — dedicated storage VLAN is high value but adds config complexity on every lab machine. Decide before migration.
- [ ] **D-Link DIR-868L** — could potentially be reflashed with OpenWrt and used as an additional WiFi AP if needed, but low priority.

## Available but Unused Network Hardware

| Device | Status | Potential Use |
|--------|--------|---------------|
| Mini PC (AMD C60) | Jumpbox / command center | SSH gateway, Claude Code, stats display |
| D-Link DIR-868L | Consumer router | Could flash OpenWrt and use as AP, or keep as spare |
| Existing consumer switches (5-port ×2, 8-port ×1, 5-port managed ×1) | Replaced by SR2024 | Spares. Workshop might keep a small switch if only one cable run goes to the garage. |
