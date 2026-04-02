# AP630 Stock Firmware Restoration

How to restore the AP630 to factory HiveOS/IQ Engine firmware from NAND backups.

## Prerequisites

- NAND backups in `~/Backups/mtd{0..9}_*.bin` (dumped before any modifications)
- Serial console access to U-Boot prompt (`/dev/ttyUSB0`, 9600 baud)
- TFTP server at 192.168.1.100 serving the backup files
- AP connected to SR2024 switch for PoE power and network

## Backup Inventory

| File | MTD | Partition | Size | Notes |
|------|-----|-----------|------|-------|
| `mtd0_uboot.bin` | mtd0 | U-Boot | 8 MB | Bootloader — only restore if U-Boot is corrupted |
| `mtd1_shmoo.bin` | mtd1 | Shmoo | 4 MB | DDR calibration — **never** overwrite unless hardware changed |
| `mtd2_hwinfo.bin` | mtd2 | Hardware Info | 1 MB | MACs, serial, hw revision — **never** overwrite |
| `mtd3_nvram.bin` | mtd3 | NVRAM | 1 MB | U-Boot NVRAM |
| `mtd4_kernel.bin` | mtd4 | Kernel Image | 14 MB | HiveOS kernel (Linux 4.1.52) |
| `mtd5_dts.bin` | mtd5 | DTS Image | 2 MB | HiveOS device tree |
| `mtd6_appimage.bin` | mtd6 | App Image | 200 MB | HiveOS rootfs (squashfs) |
| `mtd7_ubootenv.bin` | mtd7 | U-Boot Env | 1 MB | Original was blank (all 0xFF) |
| `mtd8_bootinfo.bin` | mtd8 | Boot Info | 1 MB | Boot metadata |
| `mtd9_staticbootinfo.bin` | mtd9 | Static Boot Info | 1 MB | Static boot config |

Checksums: `~/Backups/mtd_checksums.md5`

## Restore Procedure

### Step 1: Get to U-Boot prompt

Power on the AP and interrupt the autoboot countdown by pressing any key when
"Hit any key to interrupt boot from flash" appears. Enter password: `AhNf?d@ta06`

If the AP is hung, PoE cycle it via the SR2024 switch:
```
ssh admin@192.168.1.237   # password: aerohive
interface eth1/4 pse shutdown
# wait 5 seconds
no interface eth1/4 pse shutdown
exit
```
(Requires `-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa` for SSH.)

### Step 2: Stage backup files on TFTP server

```bash
# On the laptop:
sudo cp ~/Backups/mtd4_kernel.bin /srv/tftp/
sudo cp ~/Backups/mtd5_dts.bin /srv/tftp/
sudo cp ~/Backups/mtd6_appimage.bin /srv/tftp/
sudo cp ~/Backups/mtd7_ubootenv.bin /srv/tftp/

# Ensure TFTP server is running:
sudo systemctl start tftpd-hpa

# Ensure laptop has the right IP:
sudo ip addr add 192.168.1.100/16 dev enx00e04c2c62c0
```

### Step 3: Restore U-Boot environment (mtd7)

mtd7 is at NAND offset `0xe600000` (NOT `0xe600000` — that value from the
compiled-in `erase_env` variable is for a different board config).

The original mtd7 was all 0xFF (blank). Erasing it restores compiled-in defaults
(including `boot_image` which boots HiveOS).

```
u-boot> nand erase 0xe600000 0x100000
```

**Note on Broadcom U-Boot env quirk:** The saved env at mtd7 is only used for
`bootdelay`. All other variables (`bootcmd`, `bootargs`, etc.) are reinitialized
to compiled-in defaults on every boot, regardless of what's saved. This means
the stock `bootcmd=run boot_image` will always be used for HiveOS boot, and
erasing mtd7 just resets bootdelay to the compiled-in value (5 seconds).

To keep U-Boot interruptible, write a `bootdelay=5` env instead of erasing:
```
u-boot> tftpboot 0x10000000 ubootenv_production.bin
u-boot> nand erase 0xe600000 0x100000
u-boot> nand write 0x10000000 0xe600000 0x40000
```

### Step 4: Restore kernel (mtd4)

```
u-boot> tftpboot 0x10000000 mtd4_kernel.bin
u-boot> nand erase 0xe00000 0xe00000
u-boot> nand write 0x10000000 0xe00000 $filesize
```

### Step 5: Restore device tree (mtd5)

```
u-boot> tftpboot 0x10000000 mtd5_dts.bin
u-boot> nand erase 0x1c00000 0x200000
u-boot> nand write 0x10000000 0x1c00000 $filesize
```

### Step 6: Restore rootfs (mtd6) — 200 MB, takes time

```
u-boot> tftpboot 0x10000000 mtd6_appimage.bin
u-boot> nand erase 0x1e00000 0xc800000
u-boot> nand write 0x10000000 0x1e00000 $filesize
```

**Warning:** mtd6 is 200 MB. TFTP transfer at ~1 MB/s takes ~3-4 minutes.
NAND write takes additional time. Do not power off during this step.

### Step 7: Boot stock firmware

If you restored the blank U-Boot env (step 3), use the manual boot command:
```
u-boot> nand read 0x01005000 0xe00000 0xe00000
u-boot> nand read 0x05005000 0x1c00000 0x200000
u-boot> nand read 0x02005000 0x1e00000 0x2100000
u-boot> setenv bootargs coherent_pool=4M cpuidle_sysfs_switch pci=pcie_bus_safe root=/dev/ram console=ttyS0,9600 ramdisk_size=70000 cache-sram-size=0x10000
u-boot> bootm 0x01005000 0x02005000 0x05005000
```

**Note:** For stock firmware, the DTB at `0x05005000` is fine — the HiveOS kernel
uses Broadcom's proprietary RDP driver which manages the DMA zones itself. The
DTB address issue only affects mainline Linux.

On subsequent reboots, U-Boot will boot HiveOS automatically (using compiled-in
defaults if mtd7 is blank, or using the saved `manual_boot` env if mtd7 was
restored from backup).

### Step 8: Verify

Default login: `admin` / `aerohive`

```
AH-03ca80# show version
```

Should show IQ Engine 10.6r7.

## What NOT to Restore

- **mtd0 (U-Boot):** Only if U-Boot itself is broken. Corrupting this bricks the device (requires JTAG).
- **mtd1 (Shmoo):** DDR calibration data. Never touch.
- **mtd2 (Hardware Info):** MAC addresses, serial number. Never touch.

## Minimum Restore (Quick)

If you only changed the U-Boot environment (mtd7) and haven't flashed anything
to mtd4/5/6 yet, just erase mtd7 to get back to stock:

```
u-boot> nand erase 0xe600000 0x100000
u-boot> reset
```

HiveOS will boot normally using compiled-in U-Boot defaults. Bootdelay resets
to 5 seconds (compiled-in).
