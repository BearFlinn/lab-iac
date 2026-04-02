# AP630 Debian Router Project

Repurposing an Aerohive AP630 enterprise access point as a Debian arm64 router.

## Hardware

| Component | Detail |
|-----------|--------|
| **SoC** | Broadcom BCM4906 (BCM49408 family) — dual-core ARM Cortex-A53 @ 1.8 GHz |
| **RAM** | 1 GiB DDR3-1600 |
| **NAND Flash** | 1 GiB (Micron, 0 bad blocks) |
| **Ethernet** | 2x GbE (integrated BCM4908 switch — eth0 on ExtSw P3, eth1 on ExtSw P1) |
| **WiFi** | 2x Broadcom BCM43684 (4x4:4 802.11ax) — **no open-source Linux driver** |
| **USB** | 1x USB 2.0 |
| **PoE** | 802.3at (PoE+) input confirmed |
| **TPM** | v1.2.66.16 |
| **BLE** | Integrated (reset during boot) |
| **Serial console** | 9600 baud, 8N1 (same as other Aerohive devices) |

| Identity | Value |
|----------|-------|
| **Hostname** | AH-03ca80 |
| **MAC (eth0/mgt0)** | 34:85:84:03:ca:80 |
| **MAC (eth1)** | 34:85:84:03:ca:81 |
| **Serial** | 06301809050523 |
| **Mfg date** | 2018-09-05 |
| **Board ID** | 949408EAP_MAGN |
| **MACs allocated** | 64 |
| **FCC ID** | WBV-AP630 |

Source: [WikiDevi](https://wikidevi.com/wiki/Aerohive_AP630), [FCC ID](https://fccid.io/WBV-AP630), serial console output.

## Current Firmware

| Field | Value |
|-------|-------|
| **OS** | IQ Engine 10.6r7 (build-fdaa496) |
| **Build date** | Tue Mar 26 01:42:29 UTC 2024 |
| **Backup image** | IQ Engine 10.4r3 (Dec 2021) |
| **Kernel** | Linux 4.1.52, AArch64, SMP PREEMPT |
| **BusyBox** | v1.23.0 (2019-03-21) |
| **Bootloader** | U-Boot 2017.09 (Broadcom BCM49408) |
| **Bootloader ver** | v0.0.4.71 |
| **BTRM** | v1.6 (Boot ROM, runs at 115200 baud before U-Boot switches to 9600) |

## Boot Sequence

1. **BTRM v1.6** at 115200 baud — fixed boot ROM, no interrupt possible
   - `CPU0 → L1CD → MMUI → MMUA → CODE → ZBBS → MAIN → SEND`
   - Loads and verifies U-Boot from NAND
2. **U-Boot 2017.09** at 9600 baud — **no autoboot delay, no visible interrupt prompt**
   - Board ID: `949408EAP_MAGN`
   - Loads kernel from NAND offset `0xe00000`, dtb from `0x1c00000`, rootfs from `0x1e00000`
   - Kernel: Legacy Image, AArch64, gzip, load addr `0x00080000`
   - Rootfs: Legacy Image, initramfs (ramdisk), 31.6 MiB, squashfs
3. **Linux 4.1.52** — mounts squashfs rootfs as ramdisk, brings up UBI on remaining NAND
4. **HiveOS/IQ Engine** — proprietary userland on top of BusyBox

Kernel command line: `coherent_pool=4M cpuidle_sysfs_switch pci=pcie_bus_safe root=/dev/ram console=ttyS0,9600 ramdisk_size=70000 cache-sram-size=0x10000`

## NAND Partition Layout

From `/proc/mtd` (root shell):

| MTD | Name | Offset | Size | Notes |
|-----|------|--------|------|-------|
| mtd0 | Uboot | 0x000000 | 8 MB | U-Boot bootloader — **do not touch** |
| mtd1 | shmoo | 0x800000 | 4 MB | DDR calibration data — **do not touch** |
| mtd2 | Hardware Info | 0xc00000 | 1 MB | MAC, serial, hw revision — **do not touch** |
| mtd3 | nvram | 0xd00000 | 1 MB | U-Boot NVRAM (boot-param settings) |
| mtd4 | Kernel Image | 0xe00000 | 14 MB | Linux kernel (Legacy Image format) |
| mtd5 | DTS Image | 0x1c00000 | 2 MB | Device tree blob |
| mtd6 | App Image | 0x1e00000 | 200 MB | Root filesystem (squashfs initramfs) |
| mtd7 | Uboot Env | — | 1 MB | U-Boot environment variables (writable) |
| mtd8 | Boot Info | — | 1 MB | Boot metadata |
| mtd9 | Static Boot Info | — | 1 MB | Static boot config |
| mtd10 | UBIFS | — | ~810 MB | Persistent storage, mounted at `/f` |

Filesystem layout at runtime:
```
/dev/root  on /    type squashfs (ro)    — 31.6 MB initramfs
devtmpfs   on /dev type devtmpfs (rw)
tmpfs      on /tmp type tmpfs (rw)       — 168 MB
ubi0:f     on /f   type ubifs (rw)       — 672 MB (601 MB free)
tmpfs      on /var type tmpfs (rw)       — 450 MB
```

## Root Access

### Method: CVE-2025-27229 (shell injection via ssh-tunnel)

From the HiveOS CLI (serial or SSH as admin/aerohive):

```
ssh-tunnel server 0 tunnel-port 8080 user admin password "a sh -c sh"
```

This executes twice. Type `exit` once to drop into a BusyBox root shell:

```
BusyBox v1.23.0 (2019-03-21 19:17:29 PDT) built-in shell (ash)
/tmp/home/admin # id
uid=0(root) gid=500 groups=500
```

**Affected versions:** IQ Engine 10.6r7 confirmed vulnerable. Patches released Feb 26, 2025.

Source: [mclab-hbrs/extremenetworks-aerohive-writeup](https://github.com/mclab-hbrs/extremenetworks-aerohive-writeup)

### Other methods investigated (did not work on this device)

- **`_shell` hidden command:** Patched out in IQ Engine 10.6r7 (silently returns to CLI prompt, no password prompt). Worked on HiveOS ≤10.0r8 per [Aura InfoSec](https://research.aurainfosec.io/pentest/hacking-the-hive/).
- **U-Boot password `AhNf?d@ta06`:** No bootloader prompt visible at any baud rate. U-Boot autoboot delay appears to be 0 with no interrupt mechanism exposed on serial.
- **`boot-param netboot_always`:** This is a HiveOS-level setting, not a U-Boot setting. It does NOT cause U-Boot to TFTP boot. Purpose unclear — may trigger `image_flash` after HiveOS boots (but `image_flash` doesn't exist on IQ Engine 10.6r7).

### Other CVEs available (not needed, but documented)

- **CVE-2025-27227:** Unauthenticated admin password reset via `/cmn/clientmodessidsubmit.php5` (web UI, no auth required)
- **CVE-2025-27230:** RCE via file inclusion + WiFi capture path injection (more complex, requires WiFi)

## Network Setup

The AP's mgt0 interface uses DHCP on eth0 (VLAN 1). Default subnet is 192.168.0.0/16.

Current lab setup:
- AP630 eth0 → SR2024 switch (PoE power + management network)
- AP630 eth1 → available (currently unused)
- MSI laptop USB-eth adapter → SR2024 switch
- Laptop static IP: 192.168.1.100/16 on enx00e04c2c62c0
- AP DHCP address: 192.168.1.210 (from dnsmasq on laptop)
- Console: /dev/ttyUSB0 at 9600 baud

Services running on laptop:
- dnsmasq: DHCP on 192.168.1.200-250 (enx00e04c2c62c0)
- tftpd-hpa: TFTP on /srv/tftp (port 69)
- SSH: available for SCP transfers

## Debian Install Plan

### Goal
Boot Debian arm64 directly from NAND. No WiFi (use existing AP230/AP130 for that). Use as a Linux router with nftables, systemd-networkd, dnsmasq, etc.

### Approach

With root shell access via CVE-2025-27229, we can write directly to NAND:

1. **Prepare on laptop:**
   - Build or obtain a mainline arm64 kernel with BCM4908 support (CONFIG_ARCH_BCM4908)
   - Build a device tree for the AP630 (adapt from bcm4908 OpenWrt DTS or mainline)
   - Create a minimal Debian arm64 rootfs (debootstrap)
   - Wrap kernel in U-Boot Legacy Image format (mkimage)

2. **Transfer to AP:**
   - SCP or TFTP files to the AP (network is working, root shell available)
   - Or: mount a USB drive on the AP to stage larger files

3. **Flash to NAND (from root shell):**
   - Write new kernel to mtd4 (Kernel Image, 14 MB)
   - Write new DTB to mtd5 (DTS Image, 2 MB)
   - Write new rootfs to mtd6 (App Image, 200 MB) — or use UBI on mtd10 (~810 MB)
   - **Do NOT touch** mtd0 (U-Boot), mtd1 (shmoo), mtd2 (Hardware Info)

4. **U-Boot environment:**
   - Modify mtd7 (Uboot Env) to set `bootdelay=3` for future bootloader access
   - Adjust `bootcmd` if needed to load from new partition layout
   - `fw_printenv` is not on the device — need to use `nanddump`/`nandwrite` or install it

5. **Reboot into Debian**

### Key risks
- Bricking: If U-Boot is corrupted, recovery requires JTAG. **Do not write to mtd0.**
- Wrong kernel/DTB: Device won't boot. Recovery via TFTP if we set `bootdelay>0` in U-Boot env first.
- NAND wear: Use UBI/UBIFS for the rootfs to handle wear leveling and bad blocks.

### U-Boot Access (ACHIEVED)

Writing a `bootdelay=5` environment to mtd7 (previously blank/0xff) enabled the autoboot prompt:

```
Hit any key to interrupt boot from flash:  3  2  1  0
```

U-Boot reads the env from mtd7 successfully ("Using default environment" no longer appears). Pressing any key during the countdown will drop to the U-Boot prompt, enabling TFTP boot, partition reflash, and full recovery. This is our safety net — the device is now essentially unbrickable as long as mtd0 (U-Boot) and mtd1 (shmoo) are intact.

**U-Boot password:** `AhNf?d@ta06` (from Aura InfoSec disclosure, confirmed working)

**Lesson learned:** The generic `boot` command runs Broadcom's `boot_image` function which rewrites the NAND partition table and expects JFFS2/UBI with `vmlinux.lz`. This is incompatible with Aerohive's fixed-offset image layout and **will break the boot**. Always use `run manual_boot` or `bootm` with explicit addresses instead.

**Current env (mtd7):**
```
bootdelay=5
bootcmd=run manual_boot
manual_boot=nand read 0x01005000 0xe00000 0xe00000; nand read 0x05005000 0x1c00000 0x200000; nand read 0x02005000 0x1e00000 0x2100000; setenv bootargs coherent_pool=4M cpuidle_sysfs_switch pci=pcie_bus_safe root=/dev/ram console=ttyS0,9600 ramdisk_size=70000 cache-sram-size=0x10000; bootm 0x01005000 0x02005000 0x05005000
```

**Env format:**
- 4-byte CRC32 (LE) + null-terminated `key=value\0` pairs + `\0\0` + `0xff` padding
- Size: 0x40000 (256 KB), env capacity: 65532 bytes
- NAND offset: `0xe600000` (mtd7) — NOT `0x3fc0000` (that's from a different board config)

**Broadcom U-Boot env quirk:** The saved env on NAND is read for `bootdelay` (autoboot countdown), but then the environment is reinitialized to compiled-in defaults before `bootcmd` runs. This means:
- `bootdelay` CAN be persisted (tested: saved `bootdelay=3`, countdown showed 3)
- `bootcmd` and all other variables CANNOT be persisted — they always reset to compiled-in defaults
- `saveenv` from the U-Boot prompt saves compiled-in defaults, not runtime-modified values
- Recovery strategy: rely on `bootdelay=5` for the autoboot interrupt window; TFTP fallback must be entered manually

**NAND backups:** All partitions mtd0-mtd9 dumped to USB drive with MD5 checksums before any modifications. mtd6 (200MB rootfs) included.

### Kernel Boot Issue (RESOLVED)

**Root cause:** Two DTB problems caused silent early crashes:
1. `enable-method = "spin-table"` on cpu@0 (the boot CPU) — caused immediate hang
2. Missing `reserved-memory` nodes for Broadcom's RDP DMA engine — caused memory corruption

**Fix:** Custom DTS (`bcm4906-aerohive-ap630.dts`) removes `enable-method` from cpu@0 and adds `reserved-memory` nodes matching the HiveOS DTB's RDP regions.

**Also required:** `bootm` (not `booti`) — Broadcom's U-Boot `booti` doesn't properly hand off to the kernel. And the kernel must be under ~16 MB uncompressed to fit `CONFIG_SYS_BOOTM_LEN`.

### Silent Boot Crash (RESOLVED 2026-03-30)

**Root cause:** A build bug in `rebuild-and-stage.sh` copied the `.dts` source text to the `.dtb` file path, overwriting the compiled blob. U-Boot loaded this text file as a DTB, causing the kernel to crash silently. Initially misattributed to RDP DMA corruption at the DTB address `0x05005000`.

**Fix:** Fixed the build script to copy DTS to the `.dts` path and DTB to the `.dtb` path. Added the AP630 to the kernel Makefile so `make dtbs` actually compiles it.

**Note:** DTB at `0x05005000` works fine — confirmed by autonomous boot via `boot_image`. The RDP reserved-memory regions in the DTB prevent the kernel from using those physical ranges, but the DTB blob itself is not corrupted by RDP DMA.

### SERIAL_8250 Conflict (RESOLVED 2026-03-30)

**Root cause:** `CONFIG_SERIAL_8250=y` (from arm64 defconfig) registers the `ttyS` device namespace at `arch_initcall` level. When `bcm63xx_uart` tries to register the same namespace at `module_init` level, `uart_register_driver()` fails with `-EBUSY`. No error is printed — the driver silently fails, no `/dev/ttyS0` is created, and the kernel reports "unable to open an initial console."

**Fix:** Disable `CONFIG_SERIAL_8250`, `CONFIG_SERIAL_8250_CONSOLE`, `CONFIG_SERIAL_AMBA_PL011`, and `CONFIG_SERIAL_AMBA_PL011_CONSOLE`. The BCM4908 has no 8250-compatible or PL011 UARTs.

### Kernel Boots to Initramfs Shell (2026-03-30)

Linux 6.12.0 boots fully and reaches an interactive BusyBox shell:
```
Booting Linux on physical CPU 0x0000000000 [0x420f1000]
Linux version 6.12.0 (bearf@bear-laptop) ... #2 SMP PREEMPT
Machine model: Aerohive AP630
earlycon: bcm63xx_uart0 at MMIO32 0x00000000ff800640 (options '9600')
OF: reserved mem: rdp2@3400000 (45056 KiB) nomap
OF: reserved mem: rdp1@6000000 (32768 KiB) nomap
bcm63xx_uart: probe called ... alias 'serial' id=0 ... mapped at 0xff800640
Freeing initrd memory: 2452K
Run /init as init process
=== TEST BOOT SUCCESSFUL ===
```

**Autonomous boot from NAND:** The compiled-in `boot_image` loads kernel/DTB/rootfs from the Aerohive fixed NAND offsets (mtd4/5/6) and boots with `bootm`. No custom bootcmd needed.

**TFTP boot (for testing):**
```
tftpboot 0x01005000 kernel-6.12-ap630.uboot
tftpboot 0x05005000 bcm4906-aerohive-ap630.dtb
tftpboot 0x02005000 test-initramfs.uboot
setenv bootargs earlycon=bcm63xx_uart,mmio32,0xff800640,9600 coherent_pool=4M root=/dev/ram console=ttyS0,9600 ramdisk_size=70000
bootm 0x01005000 0x02005000 0x05005000
```

**Bootargs:**
```
earlycon=bcm63xx_uart,mmio32,0xff800640,9600 coherent_pool=4M root=/dev/ram console=ttyS0,9600 ramdisk_size=70000
```

**Kernel image:** 15 MB uncompressed, 6.2 MB compressed (1.2 MB headroom under 16 MB bootm limit)

**Known warnings (non-fatal):**
- `[Firmware Bug]: Kernel image misaligned at boot` — load address 0x80000 is 512K-aligned, arm64 prefers 2MB
- `CPU1: failed to come online` — secondary CPU spin-table bring-up needs SMP patches from 6.13+
- GPIO at ff800500 probe fails with -22 — cosmetic, no GPIO needed for router use

### Ethernet Driver Status (2026-04-02)

**RESOLVED.** Ethernet fully working — ENET DMA, SF2 switch, DSA, PHYs all operational. Ping confirmed at sub-ms latency over GbE.

#### What works

- **ENET DMA** (`bcm4908_enet`): Probes at 0x80002000, DMA engine operational, packets flow
- **SF2 switch** (`bcm_sf2`): BCM4908 rev 0, 1Gbps internal link to CPU port
- **DSA framework**: `wan` (port@3, PoE jack) and `lan` (port@1) + CPU port `eth0`
- **MDIO bus** (`unimac-mdio`): PHYs detected, link auto-negotiation works
- **PMB power controller**: GMAC domain (bus=1, dev=21) powers up ENET block

#### Bug 1: IRQ ordering race in bcm4908_enet_open (FIXED in local patch)

The stock `bcm4908_enet_open()` calls `request_irq()` before `bcm4908_enet_dma_reset()`. On U-Boot systems where the RDP engine left ENET interrupts asserted, the IRQ fires immediately when `__setup_irq` re-enables local interrupts. The handler tries to access DMA registers, and on a single-CPU system this monopolizes the CPU, causing fatal RCU stalls.

Stack trace: `bcm4908_enet_open+0x64 → request_threaded_irq → __setup_irq → spin_unlock_irqrestore` (at the exact point local IRQs are re-enabled)

**Fix:** Reorder `open()`: call `gmac_init()` + `dma_reset()` + `dma_init()` BEFORE `request_irq()`. The DMA reset masks and acks all interrupts, making it safe to then register the handler. Patch in local kernel tree.

This bug affects ALL U-Boot-booted BCM4908 devices. The driver was only tested on CFE-booted devices where the RDP engine is never initialized, so DMA interrupts are never asserted at boot. OpenWrt has the same unpatched driver — all their BCM4908 testers use CFE.

#### Bug 2: DMA reset has no quiesce sequence (FIXED in local patch)

The stock `bcm4908_enet_dma_reset()` writes zeros to DMA channel config registers without halting active DMA first. On U-Boot systems where the RDP left DMA running, this is unsafe.

**Fix:** Set `PKT_HALT | BURST_HALT` on each channel, poll for `ENABLE` bit to clear (with 10ms timeout), then disable channels, assert channel reset with delay, and clear state RAM. Uses the same halt/poll pattern the driver already has in `bcm4908_enet_dma_rx_ring_disable()`.

#### Bug 3: ENET block powered off (RESOLVED 2026-04-02)

**Root cause:** The ENET DMA block at 0x80002000 is controlled by `PMB_ADDR_GMAC` (bus=1, device=21) — a **separate** BPCM power domain from the SF2 switch (`PMB_ADDR_SWITCH`, bus=1, device=10). U-Boot's `sf2gmac_remove()` calls `PowerOffDevice(PMB_ADDR_GMAC, 0)` during `bootm` cleanup (`DM_REMOVE_ACTIVE_ALL`), powering off the ENET block before Linux starts.

The mainline kernel's `bcm-pmb.c` driver had no `BCM_PMB_GMAC` support, so even with `pm_runtime_resume_and_get()` in the enet driver, the genpd framework couldn't power on the GMAC domain.

**Fix (3 files):**
1. `bcm-pmb.h`: Added `#define BCM_PMB_GMAC 0x07`
2. `bcm-pmb.c`: Added `{ .name = "gmac", .id = BCM_PMB_GMAC, .bus = 1, .device = 21 }` to `bcm_pmb_bcm4908_data[]`, handled in `bcm_pmb_power_on()` / `bcm_pmb_power_off()`
3. `bcm4906-aerohive-ap630.dts`: Changed `power-domains = <&pmb BCM_PMB_GMAC>` on enet node

**Source:** Vendor PMB address map found in `asuswrt-merlin.ng` repo: `pmc_addr_4908.h` lists `PMB_ADDR_GMAC` at bus=1/dev=21 with 1 zone. The `bcm-sf2-eth-gmac.c` U-Boot driver confirms `PowerOffDevice(PMB_ADDR_GMAC, 0)` in `sf2gmac_remove()`.

**Also fixed:**
- DSA MTU overhead: Changed `ENET_MTU_MAX` from `ETH_DATA_LEN` to `ETH_DATA_LEN + BRCM_MAX_TAG_LEN` to accommodate the 4-byte Memory DSA tag
- DTS port mapping: AP630 physical eth0 (PoE) = switch port@3, physical eth1 = port@1. Ports 0 and 2 disabled (no physical connection). Labels: `wan` (port@3) and `lan` (port@1)

**BCM4908 PMB address map (from vendor SDK):**

| Bus | Dev | Name | Zones | Notes |
|-----|-----|------|-------|-------|
| 0 | 0 | PERIPH | 4 | |
| 0 | 2 | PCIE2 | 1 | |
| 0 | 3 | RDP | 2 | Runner Data Path |
| 1 | 10 | SWITCH | 3 | SF2 switch fabric at 0x80080000 |
| 1 | 14 | PCIE0 | 1 | |
| 1 | 15 | PCIE1 | 1 | |
| 1 | 17 | USB30_2X | 4 | |
| 1 | **21** | **GMAC** | **1** | **ENET DMA at 0x80002000** |

#### Key files (local patches)

| File | Changes |
|------|---------|
| `bcm4908_enet.c` | IRQ reorder, DMA quiesce, DSA MTU fix, runtime PM |
| `bcm-pmb.c` | Added `BCM_PMB_SWITCH` + `BCM_PMB_GMAC` power domains |
| `bcm-pmb.h` | Added `BCM_PMB_SWITCH = 0x06`, `BCM_PMB_GMAC = 0x07` |
| `bcm4906-aerohive-ap630.dts` | GMAC power domain, correct port mapping (wan/lan) |

#### SMP Status (2026-04-01)

- Cherry-picked patches `cef313931d64` (cfe-stub reservation) and `95d56dfaa0dd` (cpu-release-addr move)
- Patch 2 was wrong for U-Boot: it changed `cpu-release-addr` to `0xff8` (CFE convention), but HiveOS DTB uses `0xfff8`. Reverted.
- Added `/memreserve/`-equivalent for first 128 KiB (matching HiveOS's `/memreserve/ 0 0x20000`) to protect the spin-table stub
- Still fails: `CPU1: failed in unknown state : 0x0` — the secondary CPU never responds
- Memory at `0xfff8` contains `0x0000000000000403` (not zero, not a branch instruction) — U-Boot may not park the secondary CPU via spin-table at all
- Broadcom's U-Boot likely uses a proprietary mechanism (PMB power domains?) to manage secondary CPUs, not the standard ARM spin-table protocol

### Debian Rootfs (2026-04-02)

Full Debian bookworm arm64 running from NAND as initramfs. Built with `initramfs/build-debian-rootfs.sh`.

**Included:** systemd, openssh-server, iproute2, nftables, ethtool, tcpdump, iperf3, htop, tmux, strace, curl, wget, nano, dnsutils.

**Boot procedure (from U-Boot, after BTRM interrupts autoboot):**
```
nand read 0x01005000 0xe00000 0xe00000
nand read 0x08000000 0x1c00000 0x200000
nand read 0x02005000 0x1e00000 0x5700000
setenv bootargs earlycon=bcm63xx_uart,mmio32,0xff800640,9600 coherent_pool=4M console=ttyS0,9600 rdinit=/sbin/init
bootm 0x01005000 0x02005000 0x08000000
```

**Key details:**
- `rdinit=/sbin/init` is required (initramfs looks for `/init`, Debian has `/sbin/init`)
- DTB loaded at `0x08000000` (not `0x05005000`) to avoid overlap with 87 MB rootfs at `0x02005000`
- Root password: `debian`
- SSH: port 22, root login enabled
- Networking: systemd-networkd, `wan` interface gets DHCP, MAC set to `34:85:84:03:ca:80`
- Rootfs is in RAM (initramfs) — changes lost on reboot

**BTRM autoboot issue:** The BCM4908 BTRM outputs at 115200 baud before U-Boot switches to 9600. This garbage is interpreted as keypresses at 9600, interrupting the autoboot countdown every time. Manual boot from U-Boot prompt is required until a workaround is found.

### Bandwidth Issue (2026-04-02) — HARDWARE LIMITATION

**RX throughput: ~10 Mbps.** This is an iuDMA hardware limitation, not a driver bug.

**TX throughput: ~700 Mbps** (UDP flood). This proves the DMA hardware, UMAC, SF2 switch, and PHY all operate at 1 Gbps. TCP TX is limited to ~10 Mbps because ACKs flow through the 10 Mbps RX path.

**Root cause:** The BCM4908's iuDMA is a slow management path. The data-plane throughput comes from the Runner Data Path (RDP) hardware packet accelerator, which has no mainline Linux driver. The iuDMA RX path (wire→switch→DMA→CPU) is hardware-limited to ~800 packets/sec regardless of driver configuration. The CPU is 98% idle during iperf3 — the bottleneck is purely in the hardware DMA receive path.

**Ruled out (2026-04-02 exhaustive investigation):**
- Interrupt coalescing (ack-in-ISR vs ack-in-NAPI — no difference)
- NAPI scheduling latency (`time_squeeze=0`, ksoftirqd idle)
- DMA flow control (`FLOWC_CH1_EN`, `FLOWCTL_CH1_ALLOC` — no difference with or without)
- DMA burst length (8 vs 32 — no difference)
- Ring buffer sizes (200 vs 512 — no difference)
- IOMMU overhead (`iommu.passthrough=1` — no difference)
- GMAC speed config (UMAC_CMD confirms 1000 Mbps, GMAC_STATUS confirms 1000 Mbps)
- SF2 switch IMP port (`CORE_STS_OVERRIDE_IMP=0xcb` = 1Gbps/FD/LinkUp/Override)
- `ENET_DMA_RX_OK_TO_SEND_COUNT` (default 7, tried 15 — no difference)
- Per-descriptor DMA re-enable in NAPI poll — no difference
- GRO (`napi_gro_receive`) — no throughput difference (kept for protocol efficiency)

**What works fine:** latency (0.5ms), packet processing (0% loss at 10 Mbps), link negotiation (1Gbps/Full), TX throughput (700 Mbps UDP).

**To exceed 10 Mbps RX**, one of:
- Port the proprietary RDP/Runner driver to mainline Linux (major effort, requires Broadcom NDA documentation)
- Implement XDP or hardware NAT offload in the SF2 switch (would bypass the iuDMA for forwarded traffic)
- Accept 10 Mbps as the iuDMA ceiling — sufficient for a management-plane router (DNS, DHCP, NTP, SSH) with WiFi APs handling bulk traffic

### SMP Investigation (2026-04-02)

**CPU1 cannot be brought online.** Exhaustive investigation:

1. **BIU pwr_zone_ctrl[1]** has `BLK_RESET_ASSERT` set from boot — CPU1 is in block reset
2. Clearing block reset from the kernel (via spin-table `cpu_prepare` hook) does not help — CPU1 never enters a spin loop at 0xfff8
3. `boot_image` (NAND boot) also does NOT release CPU1 — block reset is still asserted after boot_image
4. HiveOS kernel has `PowerOnZone`/`PowerOnDevice` (PMC DQM) but NO `pmc_cpu_power_up` — HiveOS likely ran single-core too
5. PMB master (MMIO at 0x802800c0) returns garbage for BIU_PLL reads — BCM4908 uses DQM mode for PMC, not direct PMB
6. The DQM (message queue) interface to the PMC is required to power on CPU1, but no mainline Linux driver exists for it

**To fix SMP**, one of:
- Port ATF's DQM-based `pmc_cpu_core_power_up()` from `bcm63xx_atf` into a kernel driver
- Build and integrate ARM Trusted Firmware into the boot chain (requires understanding BTRM secure boot)
- Use CFE instead of U-Boot (not practical — would require replacing the bootloader)

### Next Steps

- [x] Get full Debian rootfs booting — Debian bookworm with SSH, flashed to NAND
- [x] Find the ENET block's power/clock gate — `PMB_ADDR_GMAC` (bus=1, dev=21)
- [x] Add GMAC to Linux PMB driver — `BCM_PMB_GMAC`, verified working
- [x] Ethernet working — ENET DMA, SF2 switch, DSA, ping confirmed
- [x] Flash kernel + DTB + rootfs to NAND
- [x] Investigate enet bandwidth — **hardware limitation** of iuDMA RX path (~10 Mbps), TX works at 700 Mbps
- [x] Clean up enet debug prints — removed from non-error paths, added GRO
- [ ] Fix autoboot interruption (BTRM 115200 baud garbage at U-Boot 9600)
- [ ] Fix SF2 crossbar warning (`Invalid port mode` at bcm_sf2_crossbar_setup)
- [ ] Add NAND MTD partition definitions to DTS (for persistent storage on mtd10)
- [ ] Enable USB_STORAGE=y in kernel (currently =m, modules not available in initramfs)
- [ ] Fix sshd in initramfs (needs `sshd` user, host keys, sshd_config baked in)
- [ ] Port DQM PMC interface for SMP (CPU1)
- [ ] Submit AP630 DTS + driver patches to Linux kernel mailing list
- [ ] Investigate RDP/Runner hardware accelerator for line-rate forwarding

### Open Questions

- [x] USB mass storage in stock kernel? **Yes** (needs `insmod usb-storage.ko`)
- [x] U-Boot env format? **Documented** in `uboot-env/build-env.py` — 4-byte CRC32 LE + null-terminated pairs + 0xFF padding, 256 KB total
- [x] DTB: mainline or custom? **Custom** DTS (`bcm4906-aerohive-ap630.dts`) based on mainline `bcm4906.dtsi` with cpu@0 spin-table fix and RDP reserved-memory
- [x] BCM4908 ethernet driver — does it work without Broadcom's proprietary runner/flow cache? **Yes.** The ENET DMA block works standalone with the SF2 switch via DSA. No runner/flow cache needed for basic L2/L3 forwarding.
- [x] PMB SWITCH domain (bus=1/dev=10) — is it the ENET block? **No.** It's the SF2 switch fabric, not the ENET DMA.
- [x] What BPCM device / clock gate controls the ENET block at 0x80002000? **`PMB_ADDR_GMAC` (bus=1, dev=21, 1 zone).** Found in asuswrt-merlin.ng `pmc_addr_4908.h`.
- [x] Does U-Boot `eth_halt()` power off the ENET block specifically, or both ENET + switch? **ENET only.** `sf2gmac_remove()` calls `PowerOffDevice(PMB_ADDR_GMAC, 0)`. The switch stays powered.
- [ ] NAND MTD driver — `brcmnand` probes but shows empty `/proc/mtd`. Needs partition definitions in DTS.
- [x] Does `boot_image` release CPU1 from block reset? **No.** pwr_zone_ctrl[1] still has BLK_RESET_ASSERT after boot_image.
- [x] Does HiveOS use both cores? **Likely not.** No `pmc_cpu_power_up` function found in HiveOS kernel binary.

### Tooling developed

| Script | Purpose |
|--------|---------|
| `scripts/catch-uboot.py` | Reliable U-Boot catcher — spams serial at 100ms intervals, handles password. `--poe` / `--reboot`. |
| `scripts/tftp-boot-test.sh` | Full TFTP boot test harness — handles any AP state, loads kernel/DTB/initramfs, captures filtered boot log. |
| `scripts/rebuild-and-stage.sh` | Incremental kernel rebuild + gzip + mkimage + stage to /srv/tftp/. `--dtb-only` mode. |
| `scripts/power-cycle-ap.sh` | PoE cycle via SR2024 switch SSH (eth1/4). |
| `scripts/get-to-uboot.sh` | State machine — detects AP state and gets to U-Boot from any starting point. |
| `scripts/kconfig-tweak.sh` | Kernel config helper — enable/disable/module/check/size/diff/search. |
| `initramfs/build-debian-rootfs.sh` | Builds full Debian bookworm arm64 rootfs as initramfs for NAND. |
| `initramfs/build-test-initramfs.sh` | Minimal BusyBox test initramfs for kernel boot testing. |
| `initramfs/build-enet-test-initramfs.sh` | Diagnostic initramfs with modules, devmem, ethernet test harness. |
| `kernel/build.sh` | Full kernel build — downloads 6.12, configures, cross-compiles. |
| `kernel/generate-config.sh` | Generates kernel config from scratch for BCM4908. |
| `uboot-env/build-env.py` | Generates U-Boot environment images (CRC32 + key=value pairs). |

### Key technical reference

| Address | Block | Status |
|---------|-------|--------|
| `0x80002000` | ENET (DMA + UMAC + MIB) | **Working** — powered by PMB GMAC domain |
| `0x80002400` | ENET UMAC | **Working** — TX/RX enabled |
| `0x80002800` | ENET DMA controller | **Working** — descriptor rings operational |
| `0x80080000` | SF2 switch fabric | Working — BCM4908 rev 0, 1Gbps link |
| `0x800c05c0` | UniMAC MDIO | Working — PHYs detected |
| `0x802800c0` | PMB power controller | Working — BPCM read/write functional |
| PMB bus=1/dev=10 | Switch BPCM | Powered ON — SF2 switch fabric |
| PMB bus=1/dev=17 | USB BPCM | Managed by Linux PMB driver |
| PMB bus=1/dev=21 | **GMAC BPCM** | **Powered ON** — ENET DMA block |

### Stock Firmware Restoration

See `ap630-debian/RESTORE-STOCK.md` for full procedure. NAND backups of all 10 partitions (mtd0-mtd9) are in `~/Backups/` with MD5 checksums. Minimum restore: erase mtd7 from U-Boot (`nand erase 0x3fc0000 0x40000`) to return to compiled-in defaults.
