# Current Network Layout

> **IP addresses:** Authoritative values are in `ansible/group_vars/all/network.yml`.

Last updated: 2026-03-24

## Physical Topology

```
                    [Xfinity Gateway]
                  Router / DHCP / WiFi / DNS
                      Living Room
                           |
                           | (cable drop through ceiling)
                           v
                 [5-port unmanaged switch]
                       Basement
                      /    |    \
                     /     |     \
                    v      v      v
            Master      Garage    My Room
            Bedroom       |          |
            (1 drop)      v          v
                    [5-port unmgd]  [5-port managed (cheap)]
                     Workshop          |
                                       v
                                 [8-port unmgd]
                                   The Lab
                                  /  |  |  \
                                 /   |  |   \
                         Inspiron Tower MSI  Optiplex
                         (ctrl)  (wkr) (wkr) (deb-web)
```

## Current State

### Routing & DHCP
- **Everything runs through the Xfinity gateway** — routing, DHCP, DNS, WiFi
- No custom DHCP reservations or static assignments at the router level
- Machines use static IPs configured at the OS level (Ansible-managed)

### Switching
- **4 switches total**, all unmanaged except one cheap 5-port managed switch
- Daisy-chained: Xfinity → basement 5-port → room 5-port managed → 8-port unmanaged (lab)
- No VLANs, no segmentation — everything is flat on the same broadcast domain
- The managed switch in the chain isn't being used for anything managed

### WiFi
- Xfinity gateway only — single AP in the living room
- Coverage likely poor in the room/garage/workshop

### DNS
- Xfinity gateway defaults (likely Comcast's DNS or whatever is configured)
- No local DNS resolution for lab machines (they're in /etc/hosts via Ansible)

### Security
- **No network-level segmentation** — lab, personal devices, guest devices, IoT all on the same flat network
- Security is per-machine (SSH keys, firewall rules) and per-service (K8s RBAC, network policies)
- External access is via NetBird VPN tunnels through the Hetzner VPS — no ports forwarded on the Xfinity gateway
- The VPN+VPS approach actually sidesteps a lot of the problems with the flat network for external access

## What Works

- NetBird VPN for external access is solid — doesn't depend on the local network being well-configured
- Per-machine SSH security is fine
- Static IPs via Ansible means DHCP chaos doesn't affect the lab
- It's simple and nothing is broken

## What's Not Great

- **No segmentation** — a compromised IoT device or guest could reach lab machines directly
- **Daisy-chain switching** — 3 switches deep to reach the lab, any one failure kills everything downstream
- **Xfinity gateway as router** — limited control, likely no VLAN support, mediocre DNS, can't configure much
- **WiFi coverage** — single AP in the living room, likely dead spots in the room/garage
- **No local DNS** — relying on /etc/hosts is fragile and doesn't help non-lab devices
- **No dedicated storage network** — when the R730 starts serving NFS to K8s nodes, that traffic shares bandwidth with everything else
- **The managed switch is wasted** — sitting in the chain doing nothing useful

## Management Network

Out-of-band management interfaces (iDRAC, BMC/IPMI) are on the 10.0.0.x lab subnet, reachable directly. Managed via `ipmitool` (both) and `racadm` (R730 only, when HTTPS is working).

| Interface | IP | Notes |
|-----------|-----|-------|
| R730xd iDRAC | `<r730xd_idrac_ip>` | Firmware 2.40, IPMI + HTTPS working |
| Quanta BMC/IPMI | `<quanta_bmc_ip>` | Not yet verified |

## Network Equipment Available for Migration

| Equipment | Location | Notes |
|-----------|----------|-------|
| SR2024 (24-port managed GbE + 2 SFP) | New | VLAN-capable, replaces the switch chain in the lab |
| 2× Aerohive AP130 | New | PoE, standalone confirmed (HiveOS 6.5r8b / 6.5r1b) |
| 1× Aerohive AP230 | New | PoE, standalone confirmed (HiveOS 8.1r1), higher performance |
| R730 4-port NIC | In R730 | Could dedicate ports to storage network |
| Xfinity gateway | Living room | Stays as WAN/ISP handoff — question is whether to bridge it or keep it as router |
