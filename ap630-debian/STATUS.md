# AP630 Debian Router — Status

*Last updated: 2026-04-03*

## Current State

Debian bookworm arm64 boots from NAND on the AP630. Single-core Cortex-A53
at 1.8 GHz, 1 GB RAM. Kernel 6.12 with custom DTS and local driver patches.

**What works:**
- Kernel boot from NAND (manual `bootm` from U-Boot — BTRM garbage interrupts autoboot)
- Ethernet: 2x GbE via SF2 switch + DSA (`wan` on port 3, `lan` on port 1)
- Networking: systemd-networkd, DHCP on wan, ping at 0.5ms latency
- SSH (requires manual setup each boot — initramfs loses state)
- USB (host controller probes, mass storage needs `USB_STORAGE=y`)
- Serial console at 9600 baud

**What doesn't work:**
- WiFi (BCM43684 — no open-source driver exists)
- Ethernet throughput: RX capped at ~10 Mbps by iuDMA hardware (TX: 700 Mbps UDP)
- SMP: CPU1 stuck in block reset (needs DQM PMC driver)
- Autoboot: BTRM baud mismatch interrupts U-Boot countdown every time
- Persistent rootfs: initramfs, changes lost on reboot

## Throughput Summary

| Test | Result | Notes |
|------|--------|-------|
| Ping latency | 0.5 ms | Sub-ms, excellent |
| TCP TX | 10 Mbps | End-to-end throughput, iuDMA bottleneck |
| TCP RX | 9.4 Mbps | iuDMA hardware ceiling |
| UDP TX flood | 9.4 Mbps delivered | Sender reports 668 Mbps, **99% packet loss** at receiver |
| UDP RX flood | 9.5 Mbps | Same iuDMA bottleneck |
| WAN download | 868 Mbps | Laptop direct (benchmark) |

**CORRECTION (2026-04-03):** The previously reported "700 Mbps UDP TX" was the *sender*
rate, not actual delivered throughput. The receiver only gets ~9.4 Mbps with 99% loss.
The bottleneck is **bidirectional** — ~10 Mbps in both TX and RX.

### Packet-size sweep (UDP RX)

| Packet size | Delivered Mbps | Loss |
|-------------|---------------|------|
| 64 bytes    | 4.9           | 1.3% |
| 128 bytes   | 6.6           | 1.9% |
| 256 bytes   | 8.0           | 3.2% |
| 512 bytes   | 8.9           | 5.5% |
| 1024 bytes  | 9.4           | 9.8% |
| 1400 bytes  | 9.5           | 13%  |

The limit is primarily **byte-rate** (scales with packet size), not packet-rate.

### DMA register tuning results (2026-04-03)

All switch ports and the IMP/CPU port confirmed at 1000 Mbps.
UMAC confirmed at CMD_SPEED_1000. No speed misconfiguration.

| Experiment | TCP RX result | Notes |
|-----------|---------------|-------|
| Baseline | 9.41 Mbps | — |
| OK_TO_SEND = 15 (was 7) | 9.41 Mbps | No effect |
| Burst length = 16 (was 8) | 9.41 Mbps | No effect |
| Burst length = 32 | DMA crash | Unsafe hot write |
| Flow control enable | Network broken | FLOWC_CH1_EN disrupts DMA |

Conclusion: the ~10 Mbps iuDMA throughput is a **hardware limitation** of the
BCM4908 slow-path DMA engine. No register tuning can change it.
Line-rate forwarding requires the Runner Data Path (RDP) accelerator.

### RDP init results (2026-04-03)

Compiled the asuswrt-merlin.ng U-Boot RDP `data_path_init()` as a kernel module
(`rdp_full_init.ko`). The module initializes BBH, BPM, SBPM, IH, DMA, loads
Runner firmware, and enables all 4 Runner cores.

| Test | iuDMA only | With RDP init | Improvement |
|------|-----------|---------------|-------------|
| TCP RX | 9.41 Mbps | **94 Mbps** | **10x** |
| TCP TX | 10.0 Mbps | **95 Mbps** | **9.5x** |

The ~95 Mbps ceiling is CPU-bound (single Cortex-A53 @ 1.8 GHz). Even with full
Runner hardware forwarding, the CPU must process every new flow (routing lookup,
NAT, nftables). The Runner only accelerates already-classified flows (L2 bridging).
For a router with firewall rules, the CPU is always in the critical path.

**Conclusion: the AP630 is not viable as a GbE WAN router.** The 95 Mbps ceiling
is ~11% of the 868 Mbps WAN speed. The device was designed as a WiFi AP (L2
bridging), not an L3 router. See ADR 010 for the full analysis.

## Next Steps (by priority)

### Practical / Quick Wins
1. **Bake SSH into initramfs** — add `sshd` user, host keys, sshd_config to the rootfs build
2. **Add NAND MTD partitions to DTS** — enables persistent storage on mtd10 (~810 MB UBIFS)
3. **Enable `USB_STORAGE=y`** in kernel config (currently `=m`, no modules in initramfs)
4. **Fix autoboot** — investigate U-Boot env tricks or baud-rate workaround for BTRM

### Driver Cleanup for Upstream
5. **Fix SF2 crossbar warning** — port 7 mode not defined in DTS, causes `Invalid port mode` WARN
6. **Submit AP630 DTS** to linux-arm-kernel mailing list
7. **Submit enet driver fixes** (IRQ reorder, DMA quiesce, GMAC power domain) to netdev

### Performance (Major Effort — BLOCKER for router use)
8. **RDP/Runner reverse engineering** — stock firmware extracted, see `docs/rdp-reverse-engineering.md`
   - rdpa.ko has full symbols (2449), 4 firmware binaries (~32 KB each)
   - **Checked (2026-04-03):** RDPA/BDMF are binary blobs, BUT the register-level
     hardware drivers (`data_path_init.c`, `rdp_drv_bbh.c`, `rdp_drv_bpm.c`, etc.)
     and RDD layer are **full GPL source** in asuswrt-merlin.ng. Runner firmware
     available as loadable `uint32_t` C arrays. See `docs/rdp-reverse-engineering.md`.
   - Next: write minimal kernel module using GPL hardware drivers to init
     BBH+BPM+DMA, load Runner firmware, bypass BDMF/RDPA entirely
9. **SMP** — port DQM PMC `pmc_cpu_core_power_up()` from bcm63xx ATF

## Files

| Path | Purpose |
|------|---------|
| `dts/bcm4906-aerohive-ap630.dts` | Device tree (custom, based on mainline bcm4906.dtsi) |
| `kernel/patches/bcm4908_enet.c` | Patched enet driver (IRQ reorder, DMA quiesce, GMAC PMB, GRO) |
| `kernel/patches/bcm-pmb.{c,h}` | PMB driver with GMAC power domain support |
| `kernel/build.sh` | Full kernel build (download, configure, compile) |
| `kernel/generate-config.sh` | Kernel config generator |
| `scripts/rebuild-and-stage.sh` | Incremental build + TFTP staging |
| `scripts/catch-uboot.py` | Serial U-Boot catcher with password handling |
| `scripts/tftp-boot-test.sh` | TFTP boot harness (supports `--debian` mode) |
| `scripts/power-cycle-ap.sh` | PoE cycle via SR2024 switch |
| `initramfs/build-debian-rootfs.sh` | Debian bookworm arm64 rootfs builder |
| `docs/rdp-reverse-engineering.md` | RDP module catalog and RE notes |
