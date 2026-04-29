# ADR-011: AP630 Restored to Stock HiveOS — Used as WiFi AP

**Date:** 2026-04-03
**Status:** Accepted (supersedes ADR-003, reinstates ADR-001)

## Context

ADR-003 designated the AP630 as a dedicated Debian arm64 router, replacing the Tower PC's routing role. The AP630 Debian project made significant progress — Debian bookworm booted from NAND, both ethernet ports worked via DSA, and SSH was functional.

However, two hardware limitations proved fatal for the router use case:

1. **iuDMA throughput ceiling:** The mainline `bcm4908_enet` driver's iuDMA path is hardware-limited to ~10 Mbps in both directions (ADR-010). This is a slow-path DMA engine designed for control-plane traffic only.

2. **RDP ceiling:** Reverse engineering and porting the Runner Data Path (RDP) from GPL source achieved ~95 Mbps — a 10× improvement — but this hit a CPU-bound ceiling on the single available Cortex-A53 @ 1.8 GHz (the second core is stuck in block reset). For a router running nftables/NAT, the CPU is always in the path for connection setup, making 95 Mbps the practical maximum.

The WAN connection is 868 Mbps. A router capped at 95 Mbps is not acceptable.

## Decision

Restore the AP630 to stock HiveOS (IQ Engine 10.6r7) firmware and use it as a WiFi access point — its intended purpose. The Tower PC resumes the router role (reinstating ADR-001).

The AP630 was flashed back to stock on 2026-04-03 via NAND backup restoration through U-Boot TFTP.

## Consequences

- **AP630 joins the WiFi AP fleet** alongside the AP230 and two AP130s. It is the highest-performance AP in the fleet (4×4:4 MU-MIMO, 802.11ac Wave 2).
- **Tower PC is the router again.** This re-couples routing availability with GPU inference workload, but the trade-offs documented in ADR-001 remain acceptable for this self-hosted environment. *(2026-04-17 update: this has since been superseded — see [ADR-021](021-off-the-shelf-router-tower-pc-as-worker.md). Tower PC will not be the router; an off-the-shelf router is being purchased, and Tower PC joins the cluster as a plain K8s worker instead. The AP630 decision in this ADR still stands.)*
- **No WiFi from AP630 under Debian was ever possible.** The BCM43684 radios lack open-source drivers, so even if the router project had succeeded, WiFi would not have worked. Using it as an AP under stock HiveOS is the only way to leverage the radio hardware.
- **Significant engineering investment is closed out.** The Debian porting work (custom kernel, DTS, PMB driver patches, RDP reverse engineering) was extracted to its own public repo at [Grizzly-Endeavors/ap630-debian](https://github.com/Grizzly-Endeavors/ap630-debian) for reference but is no longer actively developed.
- **NAND backups remain in `~/Backups/`** and the restore script (now in the `ap630-debian` repo at `scripts/restore-stock.expect`) is tested and working, should it ever be needed again.
