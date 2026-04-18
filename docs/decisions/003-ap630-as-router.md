# ADR-003: AP630 as Lab Router (Replacing Tower PC)

**Date:** 2026-04-02
**Status:** Superseded by [ADR-011](011-ap630-restored-to-stock-wifi-ap.md) — AP630 restored to stock HiveOS for use as WiFi AP. Tower PC resumes router role (ADR-001 reinstated).

## Context

ADR-001 designated the Tower PC as the lab router alongside GPU inference. However, an Aerohive AP630 became available — a dual-GbE ARM device (BCM4906, 2× Cortex-A53 @ 1.8 GHz, 1 GB RAM) that can run Debian arm64 natively. This opens the possibility of a dedicated routing device, freeing the Tower PC to be purely a GPU inference workstation.

The AP630 Debian project has proven the hardware is viable: Linux 6.12 boots, both ethernet ports work (ENET DMA + SF2 switch + DSA), and the device can be flashed via root shell access.

## Decision

Use the AP630 running Debian arm64 as the dedicated lab router. The Tower PC becomes a pure GPU inference workstation with no routing responsibilities.

## Alternatives Considered

- **Tower PC as router (ADR-001)** — Rejected because it couples routing availability to GPU driver updates, kernel upgrades, and inference workload stability. A router reboot takes down the whole network; decoupling this from a multi-GPU workstation reduces blast radius.
- **Commercial router / mini PC** — Unnecessary cost when the AP630 hardware is already on hand and proven capable.

## Consequences

- **Dedicated routing device.** Router reboots don't affect GPU inference; GPU driver updates don't take down the network. Clean separation of concerns.
- **Low power.** The AP630 draws ~10W via PoE — far less than keeping the Tower PC on 24/7 for routing.
- **No WiFi from the AP630.** The BCM43684 radios have no open-source driver. WiFi continues to come from the AP230/AP130 fleet — this is fine since the AP630 was chosen for its ethernet/routing capability, not wireless.
- **ARM platform risk.** Mainline kernel support for BCM4908 is thin — required custom DTS, driver patches (ENET IRQ reorder, DMA quiesce, PMB GMAC power domain). Future kernel upgrades may need patch maintenance. Mitigated by documenting all patches in the [Grizzly-Endeavors/ap630-debian](https://github.com/Grizzly-Endeavors/ap630-debian) repo.
- **Single CPU core for routing.** Second core doesn't come up yet (spin-table issue). 1.8 GHz Cortex-A53 is sufficient for gigabit NAT/firewall, but leaves no headroom for CPU-intensive services on the router itself.
