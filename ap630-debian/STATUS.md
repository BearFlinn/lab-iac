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
| TCP TX | 10 Mbps | Limited by RX ACK path |
| TCP RX | 10 Mbps | iuDMA hardware ceiling |
| UDP TX flood | 700 Mbps | Near wire speed |
| UDP RX flood | 10 Mbps | Same iuDMA bottleneck |
| WAN download | 868 Mbps | Laptop direct (benchmark) |

The 10 Mbps RX limit is a hardware property of the BCM4908's iuDMA path.
Line-rate forwarding requires the Runner Data Path (RDP) accelerator.

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

### Performance (Major Effort)
8. **RDP/Runner reverse engineering** — stock firmware extracted, see `docs/rdp-reverse-engineering.md`
   - rdpa.ko has full symbols (2449), 4 firmware binaries (~32 KB each)
   - GPL source likely available in asuswrt-merlin.ng `rdp/` directory
   - Next: check GPL source, dump live registers from stock HiveOS, attempt minimal init
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
