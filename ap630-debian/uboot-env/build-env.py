#!/usr/bin/env python3
"""
Build U-Boot environment images for the Aerohive AP630.

U-Boot env format: 4-byte CRC32 (little-endian) + null-terminated key=value pairs + 0x00 0x00 + 0xff padding
Total size: 0x40000 (256 KB)

Usage:
    python3 build-env.py                  # Build the production env (NAND boot + TFTP fallback)
    python3 build-env.py --bootdelay-only # Build minimal env with just bootdelay=5

WARNING: Broadcom's U-Boot saveenv is broken on this device — it saves
compiled-in defaults instead of the runtime env. Flash from Linux instead.

Flash from AP630 root shell (HiveOS):
    wget -O /tmp/ubootenv.bin http://192.168.1.100:8080/ubootenv_production.bin
    dd if=/tmp/ubootenv.bin of=/dev/mtdblock7 bs=4096
    # Verify:
    dd if=/dev/mtdblock7 of=/tmp/verify.bin bs=4096 count=64
    md5sum /tmp/ubootenv.bin /tmp/verify.bin

Flash from U-Boot (use mtd7 offset = 0xe600000, NOT 0x3fc0000):
    tftpboot 0x10000000 ubootenv_production.bin
    nand erase 0xe600000 0x100000
    nand write 0x10000000 0xe600000 0x40000

To erase (restore to compiled-in defaults):
    From U-Boot: nand erase 0xe600000 0x100000
    From Linux:  dd if=/dev/zero of=/dev/mtdblock7 bs=4096 count=256
"""

import struct
import binascii
import hashlib
import sys

ENV_SIZE = 0x40000  # 256 KB — must match CONFIG_ENV_SIZE in U-Boot

# Memory map:
#   Kernel:    0x01005000
#   Rootfs:    0x02005000
#   DTB:       0x05005000 (matches boot_image's compiled-in address)
#
# NAND offsets (Aerohive partition layout):
#   mtd4 Kernel: 0xe00000  size 0xe00000  (14 MB)
#   mtd5 DTB:    0x1c00000 size 0x200000  (2 MB)
#   mtd6 Rootfs: 0x1e00000 size 0x2100000 (33 MB read — enough for initramfs)
#
# Boot strategy:
#   1. Try NAND boot (nand_boot) — loads kernel/DTB/rootfs from flash
#   2. If bootm fails, fall back to TFTP (net_boot) — loads from network
#   This means a bad NAND flash automatically recovers via TFTP with no
#   manual intervention, as long as the TFTP server is running.

PRODUCTION_ENV = [
    "bootdelay=5",
    "bootcmd=run nand_boot || run net_boot",

    # NAND boot: load from flash, boot with earlycon
    "nand_boot="
        "echo Booting from NAND...; "
        "nand read 0x01005000 0xe00000 0xe00000; "
        "nand read 0x05005000 0x1c00000 0x200000; "
        "nand read 0x02005000 0x1e00000 0x2100000; "
        "setenv bootargs earlycon=bcm63xx_uart,mmio32,0xff800640,9600 "
        "coherent_pool=4M root=/dev/ram console=ttyS0,9600 ramdisk_size=70000; "
        "bootm 0x01005000 0x02005000 0x05005000",

    # TFTP fallback: load from network if NAND boot fails
    "net_boot="
        "echo NAND boot failed, trying TFTP...; "
        "setenv ipaddr 192.168.1.201; "
        "setenv serverip 192.168.1.100; "
        "tftpboot 0x01005000 kernel-6.12-ap630.uboot; "
        "tftpboot 0x05005000 bcm4906-aerohive-ap630.dtb; "
        "tftpboot 0x02005000 test-initramfs.uboot; "
        "setenv bootargs earlycon=bcm63xx_uart,mmio32,0xff800640,9600 "
        "coherent_pool=4M root=/dev/ram console=ttyS0,9600 ramdisk_size=70000; "
        "bootm 0x01005000 0x02005000 0x05005000",

    # Network config (used by net_boot and manual TFTP commands)
    "ipaddr=192.168.1.201",
    "serverip=192.168.1.100",
]

BOOTDELAY_ONLY_ENV = [
    "bootdelay=5",
]


def build_env(env_vars: list[str], output_path: str):
    env_data = b'\0'.join(v.encode() for v in env_vars) + b'\0\0'

    data_size = ENV_SIZE - 4  # minus CRC
    if len(env_data) > data_size:
        print(f"ERROR: env data ({len(env_data)} bytes) exceeds capacity ({data_size} bytes)")
        sys.exit(1)

    padded_data = env_data + b'\xff' * (data_size - len(env_data))
    crc = binascii.crc32(padded_data) & 0xffffffff
    image = struct.pack('<I', crc) + padded_data

    assert len(image) == ENV_SIZE

    with open(output_path, 'wb') as f:
        f.write(image)

    md5 = hashlib.md5(image).hexdigest()
    print(f"Written: {output_path}")
    print(f"  Size: {len(image)} bytes (0x{len(image):x})")
    print(f"  CRC32: 0x{crc:08x}")
    print(f"  MD5: {md5}")
    print(f"  Env data: {len(env_data)} bytes")
    for v in env_vars:
        display = v[:120] + "..." if len(v) > 120 else v
        print(f"    {display}")


if __name__ == "__main__":
    if "--bootdelay-only" in sys.argv:
        build_env(BOOTDELAY_ONLY_ENV, "ubootenv_bootdelay5.bin")
    else:
        build_env(PRODUCTION_ENV, "ubootenv_production.bin")
