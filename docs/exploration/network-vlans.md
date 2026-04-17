# VLAN Redesign (exploration)

> **Status: not implemented.** Gated on an off-the-shelf router purchase ([ADR-021](../decisions/021-off-the-shelf-router-tower-pc-as-worker.md)). For the live topology, see [../network.md](../network.md).

Last updated: 2026-04-17

## Why this isn't live yet

The lab runs on a **flat SR2024 network** today with the Xfinity gateway upstream. The target architecture below is gated on two purchases:

1. An **off-the-shelf router** ([ADR-021](../decisions/021-off-the-shelf-router-tower-pc-as-worker.md)) to replace the Xfinity gateway's routing role. Until it's in place, configuring VLANs buys little — inter-VLAN routing would have to live somewhere, and we've explicitly decided not to run it ourselves.
2. **UPS battery replacement** (not network-blocking, tracked separately).

Nothing below is time-pressured — everything still operates on the current flat network until then.

## Physical Layout (current)

All lab machines are in the closet:

- SR2024 switch (24-port managed)
- Dell PowerEdge R730xd (storage + observability + foundation stores)
- Quanta QSSC-2ML (K8s worker)
- Intel NUC (K8s worker)
- Dell Optiplex 9020 (K8s worker)
- Dell Inspiron 15 (K8s control plane)
- Tower PC (pending K8s worker — ADR-021)

Home drops (bedroom, garage, workshop) stay on the legacy consumer switch chain ([ADR-008](../decisions/008-keep-existing-switch-chain-for-home.md)) — they're fine as they are.

## Target Topology (post-router)

```
              [ISP / Xfinity Gateway]
                 Bridge mode
                  Living Room
                        |
                        v
              +-------------------+
              |  Off-the-shelf    |
              |  Router           |
              |  NAT/DHCP/DNS/FW  |
              |  VLAN trunk       |
              +-------------------+
                        |
                        v
            +-------------------+
            |    SR2024 Switch  |
            |  24-port managed  |
            |    VLAN trunks    |
            +-------------------+
              |  |  |  |  |  |
              v  v  v  v  v  v
           Lab machines  Home drops   APs
           (VLAN 10)    (VLAN 1)     (trunk)
```

### How it works (once the router is in place)

- **Xfinity gateway in bridge mode** — passes the public IP to the purchased router, which handles all routing.
- **Purchased router** handles NAT, DHCP, DNS, and inter-VLAN firewall rules. Typical candidates (UniFi, OPNsense on an appliance) all support this out of the box.
- **SR2024 handles L2 tagging** — trunk ports to the router; access / trunk ports per lab machine.
- **Lab machines keep static IPs** (as they already do via Ansible) on the lab VLAN.

### What this unlocks

- Inter-VLAN firewall rules — granular control over what can cross VLAN boundaries.
- Custom DHCP per VLAN — static leases for lab, dynamic for home.
- Local DNS — lab-internal resolution without `/etc/hosts` hacks.
- Full router-side config, no Xfinity gateway feature limits.

## VLAN Design (deferred — target state)

Start with 2 VLANs, expand only if warranted.

| VLAN | ID | Purpose | Members |
|------|----|---------|---------|
| Default (Home) | 1 (untagged) | Home network — DHCP from new router, personal devices, internet | Router uplink, bedroom drop, garage drop, WiFi APs (home SSID), lab machines' internet-facing port |
| Lab | 10 (tagged) | Lab-internal — K8s, storage, observability | Inspiron, Quanta, Intel NUC, Optiplex, Tower PC (once joined), R730xd |

### Optional: Storage Sub-VLAN

| VLAN | ID | Purpose | Members |
|------|----|---------|---------|
| Storage | 20 | NFS / iSCSI traffic only | R730 (dedicated NIC port), worker nodes' dedicated ports |

Worth doing **if** storage I/O noticeably contends with other lab traffic on the flat network. No pressure to commit up front — the R730xd 4-port NIC makes this trivial to add when needed.

### How lab machines handle tagging

Each lab machine gets:

- **Untagged on VLAN 1** for internet / general access (default gateway via the new router).
- **Tagged VLAN 10** on the same port (802.1Q trunk) for lab-internal traffic.

Result: two IPs per machine — one on the home subnet (for internet), one on the lab subnet (for everything K8s / storage). Works cleanly with Linux's VLAN support (`ip link add link eth0 name eth0.10 type vlan id 10`).

## WiFi Architecture

| AP | Location | Notes |
|----|----------|-------|
| AP630 (primary) | Central location (living room or hallway) | Highest performance (4×4:4 MU-MIMO, 802.11ac Wave 2). Restored to stock HiveOS 2026-04-03 ([ADR-011](../decisions/011-ap630-restored-to-stock-wifi-ap.md)). |
| AP230 (secondary) | Secondary coverage zone | 3×3:3 MIMO. Starting point per [ADR-009](../decisions/009-start-with-ap230-only.md). |
| AP130 #1 | Garage/workshop | Workshop coverage. |
| AP130 #2 | Far side of house or closet area | Dead-spot coverage if needed. |

- Once the new router is in place, VLAN-tagged SSIDs (e.g., separate guest network) are fully supported.
- Xfinity WiFi can be disabled when AP coverage is verified.
- **PoE:** SR2024 provides 802.3at — no injectors needed.

## NetBird VPN

Unchanged by the router purchase:

- Admin-group operator access to the home lab (jumpbox, R730xd, K8s nodes as needed).
- Hetzner VPS is deliberately *not* in the admin group — see [ADR-019](../decisions/019-ingress-and-tls-termination.md) and `feedback_netbird_scope.md` in memory.
- Peer-to-peer; doesn't depend on the local router.

## DNS

- **Today:** `/etc/hosts` managed by Ansible on lab machines + Xfinity upstream.
- **Target (post-router):** local DNS on the new router for lab-internal names. Eliminates the `/etc/hosts` pattern.
- **Alternative:** CoreDNS / Pi-hole on K8s — rejected for now because it creates a chicken-and-egg between K8s health and DNS availability. Router-side DNS is simpler.

## Cable Runs

| From | To | Status |
|------|----|--------|
| Xfinity gateway (living room) | Closet | In place. |
| Closet (SR2024) | AP mount locations | Partial — will complete as APs get mounted. |
| Within closet | Short patch cables — all lab machines to SR2024 | Done. |

## Open Questions

- [x] ~~SR2024 VLAN capability~~ — confirmed (802.1Q, LACP, trunks).
- [x] ~~SR2024 PoE~~ — confirmed (802.3at, powers all APs without injectors).
- [x] ~~Aerohive standalone mode~~ — confirmed (`no capwap client enable`).
- [x] ~~Custom router vs. off-the-shelf~~ — decided off-the-shelf ([ADR-021](../decisions/021-off-the-shelf-router-tower-pc-as-worker.md)).
- [ ] **Router model selection** — UniFi, OPNsense appliance, or similar. Decide when ready to buy.
- [ ] **Storage VLAN worth it?** — revisit once router is in and we have traffic baselines.
- [ ] **Xfinity gateway bridge-mode compatibility** — verify with the chosen router before cutover.

## Available but Unused Network Hardware

| Device | Status | Potential Use |
|--------|--------|---------------|
| D-Link DIR-868L | Consumer router | OpenWrt AP candidate, low priority. |
| Existing consumer switches (5-port ×2, 8-port ×1, 5-port managed ×1) | In use for home drops per ADR-008. | Leave in place. |
