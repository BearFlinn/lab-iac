# ADR 010: AP630 iuDMA 10 Mbps Limit Requires RDP for Router Use

**Date:** 2026-04-03
**Status:** Accepted — AP630 ruled out as WAN router

## Context

The AP630 (BCM4906/BCM4908) runs Debian with a mainline kernel and the
`bcm4908_enet` driver using iuDMA for packet I/O. The goal is to replace the
Xfinity box in bridge mode, requiring near-wire-speed GbE forwarding.

## Investigation

Systematic testing confirmed that iuDMA throughput is ~10 Mbps in **both
directions** (previously, TX was incorrectly reported as 700 Mbps — that was the
sender-side rate with 99% packet loss at the receiver).

### What was tested

- **DMA register tuning** via live devmem writes on the running AP630:
  - `ENET_DMA_RX_OK_TO_SEND_COUNT`: 7→15, no effect
  - `ENET_DMA_CH_CFG_MAX_BURST`: 8→16, no effect (32 crashes DMA)
  - Flow control enable (`ENET_DMA_CTRL_CFG_FLOWC_CH1_EN`): breaks networking
- **Packet-size sweep**: throughput scales from 5 Mbps (64 byte) to 9.5 Mbps
  (1400 byte), confirming byte-rate limit
- **Switch port verification**: all ports including IMP/CPU port confirmed at
  1000 Mbps via CORE_STS_OVERRIDE registers
- **UMAC verification**: CMD_SPEED_1000, TX/RX enabled, no misconfiguration
- **Overflow counters**: zero — no drops at the ENET block level
- **Interrupt analysis**: ~844 IRQs/sec (~1 packet per interrupt, no NAPI benefit)

### GPL source avenue

The asuswrt-merlin.ng repo was checked for RDP source code. The situation is layered:
- **Binary blobs:** RDPA core (`rdpa.o`) and BDMF framework (`bdmf.o`) are
  precompiled objects — cannot be recompiled for kernel 6.12
- **Full GPL source:** The register-level hardware drivers ARE available:
  `data_path_init.c` (full init sequence), `rdp_drv_bbh.c` (362 KB, BBH config),
  `rdp_drv_bpm.c` (BPM), `rdp_drv_sbpm.c`, `rdp_drv_ih.c`, plus register headers.
  The RDD layer has 30+ source files with WL4908-specific paths.
- **Runner firmware:** Available as `uint32_t` C arrays (`runner_fw_a.c` through
  `runner_fw_d.c`), loadable directly onto the Runner RISC cores.

This means a "minimal RDP init" is feasible by bypassing BDMF/RDPA and using the
register-level drivers directly.

## Decision

The ~10 Mbps iuDMA throughput limit is a **hardware property** of the BCM4908
slow-path DMA engine. Broadcom designed it for control-plane traffic only; the
data plane was always intended to use the Runner Data Path (RDP).

The AP630 **cannot serve as a GbE router** without RDP initialization. The only
remaining path is reverse engineering the RDP from the stock firmware's rdpa.ko
module (which has full symbol tables: 2449 symbols including rdd_*, fi_bl_drv_*,
and 4 embedded firmware binaries).

## Consequences

- The AP630 is not usable as a primary router in its current state
- RDP init was successfully ported as a kernel module (rdp_full_init.ko),
  achieving ~95 Mbps — a 10x improvement over iuDMA's 10 Mbps
- However, 95 Mbps is CPU-bound on the single Cortex-A53 @ 1.8 GHz
- Even with full Runner hardware forwarding (RDPA), the CPU must still
  process every new flow (routing, NAT, firewall). The Runner only
  accelerates subsequent packets in an already-classified flow.
- For a router with nftables/NAT, the CPU is always in the path for
  connection setup. ~95 Mbps is the practical ceiling for routed traffic.
- The AP630 was designed as a WiFi AP (L2 bridging), not an L3 router.
  The Runner accelerates bridging, not routing with firewall rules.
- **Conclusion: the AP630 is not viable as a GbE WAN router.**
  It should be repurposed (managed switch, low-bandwidth appliance)
  or replaced with hardware that has a faster CPU or open-source
  data plane support (e.g., x86 mini-PC, Marvell/Qualcomm SoC).
