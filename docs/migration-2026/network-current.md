# Current Network Layout

> **IP addresses:** Authoritative values are in `ansible/group_vars/all/network.yml`.

Last updated: 2026-04-17

## Physical Topology

All lab machines are in the closet on the SR2024. Non-lab drops (bedroom, garage, workshop) continue to run through the legacy consumer switch chain — see [ADR-008](../decisions/008-keep-existing-switch-chain-for-home.md).

```
                [Xfinity Gateway]
            Router / DHCP / DNS / WAN
                 Living Room
                      |
                      | (cable to closet)
                      v
          +--------------------------+
          |    SR2024 (Closet)       |
          |    24-port managed GbE   |
          |    Lab backbone          |
          +--------------------------+
              |  |  |  |  |  |
              v  v  v  v  v  v
        R730xd  Inspiron  Quanta
        (store)  (CP)     (wkr)
                 NUC      Optiplex
                 (wkr)    (wkr)
                 Tower PC (pending join)

       [Legacy consumer switch chain — home drops]
       Xfinity → basement 5-port → room 5-port mgd → 8-port unmgd
                                    bedroom/garage/workshop
```

## Current State

### Routing & DHCP

- **Xfinity gateway still handles routing, DHCP, and upstream DNS.** This is interim — an off-the-shelf router ([ADR-021](../decisions/021-off-the-shelf-router-tower-pc-as-worker.md)) will replace it, at which point the gateway goes into bridge mode.
- Lab machines use static IPs configured at the OS level (Ansible-managed).

### Switching

- **SR2024** is the lab backbone in the closet. All lab machines (live cluster + R730xd + pending Tower PC) connect directly to it.
- **Flat L2** — no VLANs configured yet. VLAN design lives in `network-target.md` and is deferred until the purchased router arrives, so inter-VLAN routing happens on the new router rather than being grafted onto the Xfinity gateway.
- Legacy consumer switches still serve the bedroom / garage / workshop drops (ADR-008).

### WiFi

- AP230 / AP130s / AP630 all factory-reset to standalone mode. Mounting and SSID config still pending (Phase 4B/4D in `migration-plan.md`).
- Xfinity gateway WiFi still active as the primary coverage pending AP mounts.
- PoE to APs will come from SR2024 once mounted (no injectors needed).

### DNS

- Xfinity gateway for upstream. Lab internal names still live in `/etc/hosts` via Ansible. Local DNS (on the future router) is a target for post-router work.

### VPN / Ingress

- **NetBird** for operator admin access (admin group: jumpbox, R730xd, K8s nodes as needed). Hetzner VPS is deliberately **not** in the admin group — see `feedback_vps_home_exposure.md` in memory and [ADR-019](../decisions/019-ingress-and-tls-termination.md).
- **Hetzner VPS → K8s cluster** ingress uses a dedicated WireGuard `/30` tunnel VPS ↔ R730xd, with iptables DNAT on R730xd forwarding only TCP 30487/30356 to the K8s NodePort. No subnet routes.

### Security

- **Flat lab network** — per-machine SSH keys, host firewalls, and K8s RBAC / network policies are the only isolation. A real segmentation story waits on the purchased router and the deferred VLAN config.
- External exposure is scoped: only the VPS is publicly reachable, and it reaches home via the point-to-point WG tunnel to R730xd on exactly two TCP ports.

## Management Network

Out-of-band management (iDRAC, BMC/IPMI) lives on the lab subnet and is reachable directly from any lab-side machine.

| Interface | IP | Notes |
|-----------|-----|-------|
| R730xd iDRAC | `{{ r730xd_idrac_ip }}` | SSH racadm working; no Enterprise license (no virtual media). HTTPS web UI fine for basic monitoring. |
| Quanta BMC/IPMI | `{{ quanta_bmc_ip }}` | Static IP, dedicated NIC port. |

## Network Equipment Available

| Equipment | Location | Notes |
|-----------|----------|-------|
| SR2024 (24-port managed GbE + 2 SFP) | Closet (live) | VLAN-capable; flat today, VLANs deferred per [ADR-021](../decisions/021-off-the-shelf-router-tower-pc-as-worker.md). |
| 2× Aerohive AP130 | Spare (mount pending) | PoE, standalone-mode confirmed. |
| 1× Aerohive AP230 | Spare (mount pending) | PoE, standalone-mode confirmed. Higher performance than AP130s. |
| 1× Aerohive AP630 | Spare (mount pending) | Stock HiveOS restored 2026-04-03 ([ADR-011](../decisions/011-ap630-restored-to-stock-wifi-ap.md)). Highest-performance AP. |
| R730 4-port NIC | In R730xd | Could dedicate ports to a storage VLAN once VLANs are enabled. |
| Xfinity gateway | Living room | WAN uplink; still the router until the off-the-shelf router lands. Goes into bridge mode at that point. |
