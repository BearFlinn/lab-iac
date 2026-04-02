#!/bin/bash
# Incremental kernel rebuild + package + stage to TFTP for AP630.
# Fast path for iteration: make → gzip → mkimage → /srv/tftp/.
#
# Usage:
#   rebuild-and-stage.sh                  # Rebuild, package, stage
#   rebuild-and-stage.sh --dtb-only       # Only rebuild+stage the DTB
#
# Environment:
#   KDIR — kernel source dir (default: /tmp/ap630-debian/linux-6.12)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KDIR="${KDIR:-/tmp/ap630-debian/linux-6.12}"
JOBS="${JOBS:-$(nproc)}"
TFTP_DIR="/srv/tftp"
ARCH=arm64
CROSS=aarch64-linux-gnu-

KERNEL_OUT="kernel-6.12-ap630.uboot"
DTB_NAME="bcm4906-aerohive-ap630.dtb"
DTB_REL="broadcom/bcmbca/$DTB_NAME"
DTS_SRC="$REPO_DIR/dts/bcm4906-aerohive-ap630.dts"
MAX_IMAGE_SIZE=$((16 * 1024 * 1024))

if [[ ! -d "$KDIR" ]]; then
    echo "FAIL: kernel source not found at $KDIR"
    exit 1
fi

# Sync DTS into kernel tree and ensure it's in the Makefile
BCMBCA_DIR="$KDIR/arch/$ARCH/boot/dts/broadcom/bcmbca"
cp "$DTS_SRC" "$BCMBCA_DIR/$(basename "$DTS_SRC")"
if ! grep -q "aerohive-ap630" "$BCMBCA_DIR/Makefile"; then
    sed -i "/bcm4906-netgear-r8000p.dtb/i\\\\t\\t\\t\\t\\tbcm4906-aerohive-ap630.dtb \\\\" "$BCMBCA_DIR/Makefile"
fi
# Remove stale DTB so make rebuilds it from DTS
rm -f "$BCMBCA_DIR/$DTB_NAME"
cd "$KDIR"

if [[ "${1:-}" == "--dtb-only" ]]; then
    make ARCH=$ARCH CROSS_COMPILE=$CROSS -j"$JOBS" dtbs 2>&1 | grep -E 'error:|warning:' || true
    sudo cp "arch/$ARCH/boot/dts/$DTB_REL" "$TFTP_DIR/$DTB_NAME"
    echo "DTB staged: $(stat -c%s "$TFTP_DIR/$DTB_NAME" | numfmt --to=iec)"
    exit 0
fi

BUILD_START=$SECONDS
# Only show errors and warnings from make
MAKE_OUT=$(make ARCH=$ARCH CROSS_COMPILE=$CROSS -j"$JOBS" Image dtbs 2>&1)
BUILD_TIME=$(( SECONDS - BUILD_START ))

# Print only errors/warnings
echo "$MAKE_OUT" | grep -E '^.*(error:|warning:)' | head -20 || true

IMAGE="arch/$ARCH/boot/Image"
if [[ ! -f "$IMAGE" ]]; then
    echo "FAIL: Image not built"
    echo "$MAKE_OUT" | tail -10
    exit 1
fi

IMAGE_SIZE=$(stat -c%s "$IMAGE")
if [[ $IMAGE_SIZE -gt $MAX_IMAGE_SIZE ]]; then
    OVER=$(( (IMAGE_SIZE - MAX_IMAGE_SIZE) / 1024 ))
    echo "FAIL: Image $(numfmt --to=iec $IMAGE_SIZE) — ${OVER}K over 16M limit"
    exit 1
fi

# Package
gzip -c "$IMAGE" > /tmp/ap630-kernel.gz
mkimage -A arm64 -T kernel -C gzip -a 0x00080000 -e 0x00080000 \
    -n "Linux-6.12-ap630" -d /tmp/ap630-kernel.gz /tmp/$KERNEL_OUT > /dev/null

# Stage
sudo cp /tmp/$KERNEL_OUT "$TFTP_DIR/$KERNEL_OUT"
sudo cp "arch/$ARCH/boot/dts/$DTB_REL" "$TFTP_DIR/$DTB_NAME"
rm -f /tmp/ap630-kernel.gz

HEADROOM=$(( (MAX_IMAGE_SIZE - IMAGE_SIZE) / 1024 ))
UBOOT_SIZE=$(stat -c%s "$TFTP_DIR/$KERNEL_OUT" | numfmt --to=iec)
echo "OK: ${BUILD_TIME}s | Image $(numfmt --to=iec $IMAGE_SIZE)/16M (${HEADROOM}K free) | uboot ${UBOOT_SIZE} | staged to $TFTP_DIR"
