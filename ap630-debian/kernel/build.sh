#!/bin/bash
# Full kernel build for AP630: download source, configure, compile, package, stage.
#
# Usage:
#   build.sh              # Full build (download + configure + compile)
#   build.sh rebuild      # Recompile only (source already configured)
#   build.sh config-only  # Download + configure, don't compile
#
# The saved config (config-6.12-ap630) can be used directly if generate-config.sh
# isn't needed:
#   cp kernel/config-6.12-ap630 /tmp/ap630-debian/linux-6.12/.config
#   make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
#
# Prerequisites:
#   sudo apt-get install gcc-aarch64-linux-gnu flex bison libssl-dev bc \
#       libelf-dev u-boot-tools device-tree-compiler

set -euo pipefail

KVER="6.12"
WORK="/tmp/ap630-debian"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DTS_SRC="$REPO_DIR/dts/bcm4906-aerohive-ap630.dts"
ARCH=arm64
CROSS=aarch64-linux-gnu-

mkdir -p "$WORK"

if [ "${1:-}" != "rebuild" ]; then
    if [ ! -f "$WORK/linux-${KVER}.tar.xz" ]; then
        echo "Downloading kernel ${KVER}..."
        wget -q -O "$WORK/linux-${KVER}.tar.xz" \
            "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KVER}.tar.xz"
        echo "Done ($(stat -c%s "$WORK/linux-${KVER}.tar.xz" | numfmt --to=iec))"
    fi

    if [ ! -d "$WORK/linux-${KVER}" ]; then
        echo "Extracting..."
        tar xf "$WORK/linux-${KVER}.tar.xz" -C "$WORK"
    fi

    cd "$WORK/linux-${KVER}"

    # Use saved config if it exists and generate-config.sh hasn't changed,
    # otherwise regenerate from scratch
    SAVED_CONFIG="$SCRIPT_DIR/config-6.12-ap630"
    if [ -f "$SAVED_CONFIG" ]; then
        echo "Using saved config..."
        cp "$SAVED_CONFIG" .config
        make ARCH=$ARCH CROSS_COMPILE=$CROSS olddefconfig > /dev/null 2>&1
    else
        echo "Generating config from scratch..."
        bash "$SCRIPT_DIR/generate-config.sh"
    fi

    if [ "${1:-}" = "config-only" ]; then
        echo "Config ready at $WORK/linux-${KVER}/.config"
        exit 0
    fi
else
    cd "$WORK/linux-${KVER}"
fi

# Sync DTS
cp "$DTS_SRC" "arch/$ARCH/boot/dts/broadcom/bcmbca/"

# Build + stage
export KDIR="$WORK/linux-${KVER}"
bash "$REPO_DIR/scripts/rebuild-and-stage.sh"
