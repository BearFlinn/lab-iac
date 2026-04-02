#!/bin/bash
# Build a minimal BusyBox-based test initramfs for the AP630.
# This is for testing kernel boot only — not a real rootfs.
#
# Prerequisites:
#   - A Debian arm64 rootfs at $ROOTFS_DIR (from debootstrap)
#     OR arm64 busybox/libc binaries available
#
# Usage:
#   bash build-test-initramfs.sh /path/to/arm64/rootfs
#
# Output:
#   test-initramfs.cpio.gz  — raw cpio archive
#   test-initramfs.uboot    — mkimage-wrapped for U-Boot bootm

set -euo pipefail

ROOTFS_DIR="${1:-/usr/aarch64-linux-gnu}"
WORK_DIR="$(mktemp -d)"
trap "rm -rf $WORK_DIR" EXIT

# Create directory structure
mkdir -p "$WORK_DIR"/{bin,sbin,etc,proc,sys,dev,tmp,mnt,lib/aarch64-linux-gnu}

# Copy busybox — try rootfs first, fall back to cross-compile sysroot
if [ -f "$ROOTFS_DIR/bin/busybox" ]; then
    cp "$ROOTFS_DIR/bin/busybox" "$WORK_DIR/bin/"
elif [ -f "/usr/aarch64-linux-gnu/bin/busybox" ]; then
    cp /usr/aarch64-linux-gnu/bin/busybox "$WORK_DIR/bin/"
else
    echo "No arm64 busybox found" >&2; exit 1
fi

# Copy all libraries busybox needs (resolve dynamically)
SYSROOT="${ROOTFS_DIR}"
[ -f "$SYSROOT/lib/ld-linux-aarch64.so.1" ] || SYSROOT="/usr/aarch64-linux-gnu"

cp "$SYSROOT/lib/ld-linux-aarch64.so.1" "$WORK_DIR/lib/"
# Copy all .so files that busybox needs
for lib in libc.so.6 libresolv.so.2 libm.so.6; do
    src="$SYSROOT/lib/aarch64-linux-gnu/$lib"
    [ -f "$src" ] || src="$SYSROOT/lib/$lib"
    [ -f "$src" ] && cp "$src" "$WORK_DIR/lib/aarch64-linux-gnu/" || true
done

# iproute2 and its libs if available
if [ -f "$ROOTFS_DIR/sbin/ip" ]; then
    cp "$ROOTFS_DIR/sbin/ip" "$WORK_DIR/sbin/"
    for lib in libmnl.so.0 libcap.so.2 libelf.so.1 libbpf.so.1 libselinux.so.1; do
        src="$ROOTFS_DIR/lib/aarch64-linux-gnu/$lib"
        [ -f "$src" ] && cp "$src" "$WORK_DIR/lib/aarch64-linux-gnu/" || true
    done
fi

# Create init script
cat > "$WORK_DIR/init" << 'INITEOF'
#!/bin/busybox sh
echo "=== AP630 Debian Test Boot ==="
/bin/busybox --install -s /bin
/bin/busybox --install -s /sbin

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

echo "=== Kernel ==="
uname -a

echo "=== CPU ==="
cat /proc/cpuinfo | head -10

echo "=== Memory ==="
free -m 2>/dev/null || cat /proc/meminfo | head -5

echo "=== Network interfaces ==="
ip link show 2>/dev/null || ifconfig -a 2>/dev/null || ls /sys/class/net/

echo "=== MTD partitions ==="
cat /proc/mtd 2>/dev/null || echo "No MTD"

echo "=== USB ==="
ls /sys/bus/usb/devices/ 2>/dev/null || echo "No USB"

echo ""
echo "=== TEST BOOT SUCCESSFUL ==="
echo "=== Dropping to shell — type 'poweroff' to shut down ==="
exec /bin/sh
INITEOF
chmod +x "$WORK_DIR/init"

# Build cpio archive
cd "$WORK_DIR"
find . | cpio -o -H newc 2>/dev/null | gzip > /tmp/test-initramfs.cpio.gz

# Wrap for U-Boot
mkimage -A arm64 -T ramdisk -C gzip -n "Debian test initramfs" \
    -d /tmp/test-initramfs.cpio.gz \
    /tmp/test-initramfs.uboot

echo ""
echo "=== Output files ==="
ls -lh /tmp/test-initramfs.cpio.gz /tmp/test-initramfs.uboot
echo ""
echo "Copy to TFTP server:"
echo "  sudo cp /tmp/test-initramfs.uboot /srv/tftp/"
