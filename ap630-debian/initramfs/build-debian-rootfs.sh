#!/bin/bash
# Build a Debian arm64 rootfs for the AP630 router.
# Uses debootstrap to create a real Debian system with SSH, networking,
# and diagnostic tools. Packaged as an initramfs for NAND boot.
#
# Prerequisites:
#   - debootstrap, qemu-user-static (for arm64 chroot)
#   - mkimage (u-boot-tools)
#
# Usage:
#   sudo bash build-debian-rootfs.sh
#
# Output:
#   /tmp/ap630-debian-rootfs.uboot  — mkimage-wrapped for NAND flash

set -euo pipefail

SUITE="bookworm"
ROOTFS="/tmp/ap630-rootfs"
OUTPUT="/tmp/ap630-debian-rootfs.uboot"
AP_MAC="34:85:84:03:ca:80"
AP_HOSTNAME="ap630"

# mtd6 is 200 MB — compressed rootfs must fit
MAX_SIZE=$((190 * 1024 * 1024))

echo "=== Building Debian $SUITE arm64 rootfs ==="

# Clean previous build
rm -rf "$ROOTFS"

# debootstrap
debootstrap --arch=arm64 --variant=minbase \
    --include=systemd,systemd-sysv,dbus,kmod,procps,udev \
    "$SUITE" "$ROOTFS" http://deb.debian.org/debian

echo "=== Configuring rootfs ==="

# Hostname
echo "$AP_HOSTNAME" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" << EOF
127.0.0.1 localhost
127.0.1.1 $AP_HOSTNAME
EOF

# Serial console
mkdir -p "$ROOTFS/etc/systemd/system/getty@ttyS0.service.d"
cat > "$ROOTFS/etc/systemd/system/getty@ttyS0.service.d/override.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' --keep-baud 9600 %I \$TERM
EOF
ln -sf /lib/systemd/system/getty@.service \
    "$ROOTFS/etc/systemd/system/getty.target.wants/getty@ttyS0.service"

# Root password: "debian" (change on first login)
chroot "$ROOTFS" sh -c 'echo "root:debian" | chpasswd'

# Network: systemd-networkd config
mkdir -p "$ROOTFS/etc/systemd/network"

# WAN interface (port@3, PoE cable)
cat > "$ROOTFS/etc/systemd/network/10-wan.network" << EOF
[Match]
Name=wan

[Network]
DHCP=ipv4

[Link]
MACAddress=$AP_MAC
EOF

# Enable systemd-networkd and resolved
chroot "$ROOTFS" systemctl enable systemd-networkd
chroot "$ROOTFS" systemctl enable systemd-resolved
chroot "$ROOTFS" systemctl enable ssh

# DNS
ln -sf /run/systemd/resolve/stub-resolv.conf "$ROOTFS/etc/resolv.conf"

# fstab (tmpfs only — rootfs is in RAM)
cat > "$ROOTFS/etc/fstab" << EOF
# AP630 initramfs rootfs — all in RAM
tmpfs /tmp  tmpfs defaults,nosuid,nodev 0 0
tmpfs /run  tmpfs defaults,nosuid,nodev 0 0
proc  /proc proc  defaults 0 0
sysfs /sys  sysfs defaults 0 0
EOF

# Install additional packages via chroot
chroot "$ROOTFS" apt-get update -qq
chroot "$ROOTFS" apt-get install -y --no-install-recommends \
    openssh-server \
    iproute2 nftables ethtool tcpdump iperf3 \
    htop tmux less nano curl wget \
    strace \
    net-tools iputils-ping dnsutils \
    pciutils usbutils \
    ca-certificates \
    2>&1 | grep -E "^(Setting up|Unpacking)" | head -30
echo "  ..."

# SSH config (AFTER openssh-server install so postinst doesn't overwrite)
cat > "$ROOTFS/etc/ssh/sshd_config" << EOF
Port 22
PermitRootLogin yes
PasswordAuthentication yes
UsePAM yes
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

# Ensure sshd privilege separation user exists (openssh-server postinst usually creates
# this, but it may fail in a debootstrap chroot without a running init system)
chroot "$ROOTFS" useradd -r -d /run/sshd -s /usr/sbin/nologin sshd 2>/dev/null || true
mkdir -p "$ROOTFS/run/sshd"

# Re-generate host keys (postinst may have failed to generate them in chroot)
rm -f "$ROOTFS"/etc/ssh/ssh_host_*
chroot "$ROOTFS" ssh-keygen -A

# Clean up to save space
chroot "$ROOTFS" apt-get clean
rm -rf "$ROOTFS/var/lib/apt/lists"/*
rm -rf "$ROOTFS/usr/share/doc"/*
rm -rf "$ROOTFS/usr/share/man"/*
rm -rf "$ROOTFS/usr/share/locale"/!(en|C)
rm -rf "$ROOTFS/var/cache"/*
rm -rf "$ROOTFS/var/log"/*

echo "=== Rootfs size ==="
du -sh "$ROOTFS"

echo "=== Building initramfs ==="
cd "$ROOTFS"
find . | cpio -o -H newc 2>/dev/null | gzip -1 > /tmp/ap630-rootfs.cpio.gz

CPIO_SIZE=$(stat -c%s /tmp/ap630-rootfs.cpio.gz)
echo "Compressed: $(numfmt --to=iec $CPIO_SIZE)"

if [ "$CPIO_SIZE" -gt "$MAX_SIZE" ]; then
    echo "FAIL: rootfs $(numfmt --to=iec $CPIO_SIZE) exceeds mtd6 limit $(numfmt --to=iec $MAX_SIZE)"
    exit 1
fi

mkimage -A arm64 -T ramdisk -C gzip \
    -n "Debian $SUITE arm64 AP630" \
    -d /tmp/ap630-rootfs.cpio.gz \
    "$OUTPUT"

echo ""
echo "=== Output ==="
ls -lh "$OUTPUT"
echo ""
echo "Flash to NAND (from U-Boot):"
echo "  sudo cp $OUTPUT /srv/tftp/debian-rootfs.uboot"
echo "  tftpboot 0x10000000 debian-rootfs.uboot"
echo "  nand erase 0x1e00000 0xc800000"
echo "  nand write 0x10000000 0x1e00000 <round up to 0x1000>"
echo ""
echo "Boot from U-Boot (NAND):"
echo "  nand read 0x01005000 0xe00000 0xe00000"
echo "  nand read 0x08000000 0x1c00000 0x200000"
echo "  nand read 0x02005000 0x1e00000 0x5700000"
echo "  setenv bootargs earlycon=bcm63xx_uart,mmio32,0xff800640,9600 coherent_pool=4M console=ttyS0,9600 rdinit=/sbin/init"
echo "  bootm 0x01005000 0x02005000 0x08000000"
echo ""
echo "NOTE: rdinit=/sbin/init is required — initramfs looks for /init by default,"
echo "      but Debian uses /sbin/init (systemd)."
