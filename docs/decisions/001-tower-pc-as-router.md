# ADR-001: Tower PC as Lab Router

**Date:** 2026-03-27
**Status:** Superseded by [ADR-021](021-off-the-shelf-router-tower-pc-as-worker.md) (2026-04-17). Previous history: reinstated by [ADR-011](011-ap630-restored-to-stock-wifi-ap.md) after ADR-003 closed out.

## Context

The lab migration needs a router to replace the Xfinity gateway's routing role. The gateway will be put into bridge mode so we get full control over NAT, DHCP, DNS, firewall rules, and inter-VLAN routing. The question is what hardware to run it on.

Options considered:
1. **Dedicated thin client or mini PC** — buy or repurpose a low-power x86 box solely for routing
2. **Tower PC (chosen)** — consolidate routing onto the existing tower PC alongside its GPU inference workload
3. **VM on R730** — run a router VM on the storage server
4. **Keep Xfinity as router** — no custom routing, limited VLAN and firewall control

## Decision

Use the Tower PC as the lab router in addition to its GPU inference role.

## Rationale

- **CPU is underutilized.** GPU inference workloads are GPU-bound, not CPU-bound. The tower PC's CPU will be largely idle — more than enough headroom for routing, NAT, DHCP, and DNS at gigabit speeds.
- **Already outside the cluster.** The tower PC is standalone (removed from K8s), so a router reboot doesn't affect cluster availability.
- **Non-critical co-tenants.** The other workloads on the tower PC (LLM inference) are non-critical. If the router needs a restart, the only impact is a brief inference outage — acceptable for a homelab.
- **No additional hardware.** Avoids buying or dedicating another machine solely for routing.
- **Full routing capability.** An x86 box with multiple NICs can run nftables/iptables, dnsmasq or Unbound, and handle inter-VLAN routing (router-on-a-stick via the SR2024).

## Trade-offs

- **Single point of failure.** If the tower PC goes down, the entire network loses routing (and therefore internet). Mitigation: the tower PC is on a UPS, and GPU inference restarts are infrequent.
- **Reboot = network outage.** GPU driver updates or kernel upgrades that require a reboot will briefly take down the network. Mitigation: schedule reboots during low-usage windows.
- **Complexity on one box.** Routing + GPU inference + NVIDIA drivers on the same machine is more moving parts. Mitigation: routing is a lightweight service (nftables + dnsmasq), and separation of concerns is maintained at the service level.

## Alternatives Rejected

- **Dedicated box:** Unnecessary cost and power draw for a homelab. The tower PC handles this with no additional hardware.
- **R730 VM:** Puts routing behind the storage server's availability. R730 reboots (firmware updates, drive changes) would take down the network. The R730 is more likely to need maintenance than the tower PC.
- **Keep Xfinity routing:** Loses inter-VLAN firewall rules, custom DNS, per-VLAN DHCP, and full network control — the main reasons for the migration.

---

## Update (2026-04-17) — Superseded

This decision is superseded by [ADR-021](021-off-the-shelf-router-tower-pc-as-worker.md). Two reasons:

1. The Tower PC PSU can't carry the planned GPU fleet. A separate machine is being built for GPU inference, so the "CPU idle alongside GPU inference" rationale no longer applies.
2. The operator decided the ongoing overhead of owning a DIY router in IaC isn't worth it for this homelab. An off-the-shelf router will replace the Xfinity gateway's routing role; the Tower PC will join the cluster as a plain K8s worker.

See ADR-021 for the replacement decision and context.
