#!/bin/bash
# Build a diagnostic initramfs for AP630 ethernet testing.
#
# Includes: busybox, devmem, kernel modules (.ko), test scripts.
# The init script runs diagnostics and drops to shell for manual testing.
#
# Usage:
#   bash build-enet-test-initramfs.sh [/path/to/kernel/build]
#
# Expects kernel built with CONFIG_BCM4908_ENET=m, CONFIG_NET_DSA*=m.

set -euo pipefail

KDIR="${1:-/tmp/ap630-debian/linux-6.12}"
ROOTFS_DIR="/usr/aarch64-linux-gnu"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap "rm -rf $WORK_DIR" EXIT

echo "=== Building ethernet test initramfs ==="
echo "  Kernel: $KDIR"

# Verify modules exist
ENET_MOD="$KDIR/drivers/net/ethernet/broadcom/bcm4908_enet.ko"
if [[ ! -f "$ENET_MOD" ]]; then
    echo "FAIL: $ENET_MOD not found — did you build with CONFIG_BCM4908_ENET=m?"
    exit 1
fi

# Directory structure
mkdir -p "$WORK_DIR"/{bin,sbin,etc,proc,sys,dev,tmp,mnt,lib/aarch64-linux-gnu,lib/modules}

# BusyBox (static arm64 — no shared libs needed)
BUSYBOX="/bin/busybox"
if ! file "$BUSYBOX" 2>/dev/null | grep -q "aarch64"; then
    echo "FAIL: $BUSYBOX is not arm64 — install busybox-static:arm64"
    exit 1
fi
cp "$BUSYBOX" "$WORK_DIR/bin/"

# Kernel modules — collect all the enet/DSA chain
echo "Collecting kernel modules..."
MOD_COUNT=0
for mod in \
    drivers/net/ethernet/broadcom/bcm4908_enet.ko \
    net/dsa/dsa_core.ko \
    net/dsa/tag_brcm.ko \
    net/dsa/tag_none.ko \
    drivers/net/dsa/b53/b53_common.ko \
    drivers/net/dsa/b53/b53_srab.ko \
    drivers/net/dsa/bcm-sf2.ko \
; do
    src="$KDIR/$mod"
    if [[ -f "$src" ]]; then
        cp "$src" "$WORK_DIR/lib/modules/"
        MOD_COUNT=$((MOD_COUNT + 1))
    fi
done
echo "  $MOD_COUNT modules collected"

# Test script — embedded in initramfs
cat > "$WORK_DIR/bin/enet-test" << 'TESTEOF'
#!/bin/busybox sh
# AP630 Ethernet diagnostic test suite.
# Runs from initramfs after kernel boot.
#
# Usage: enet-test [attack_num]
#   1 = baseline (just load module, try ifup)
#   2 = devmem DMA quiesce before module load
#   3 = just load module (patched driver does quiesce internally)
#   4 = no DSA — load only bcm4908_enet, skip SF2/B53
#   5 = dump DMA state only (no module load)
#   all = run attacks 1-4 sequentially
# Default: 5 (dump only)

ENET_BASE=0x80002000
DMA_BASE=0x80002800
# Register offsets from DMA_BASE
DMA_CTRL_CFG=0x80002800
DMA_CTRL_CH_RESET=0x80002834
DMA_CTRL_CH_DEBUG=0x80002838
DMA_GLOB_IRQ_STAT=0x80002840
DMA_GLOB_IRQ_MASK=0x80002844
# Channel 0 (RX)
DMA_CH0_CFG=0x80002a00
DMA_CH0_INT_STAT=0x80002a04
DMA_CH0_INT_MASK=0x80002a08
DMA_CH0_MAX_BURST=0x80002a0c
# Channel 0 state RAM
DMA_CH0_SR_BASE=0x80002c00
DMA_CH0_SR_STATE=0x80002c04
DMA_CH0_SR_LEN=0x80002c08
DMA_CH0_SR_BUF=0x80002c0c
# Channel 1 (TX)
DMA_CH1_CFG=0x80002a10
DMA_CH1_INT_STAT=0x80002a14
DMA_CH1_INT_MASK=0x80002a18
DMA_CH1_MAX_BURST=0x80002a1c
# Channel 1 state RAM
DMA_CH1_SR_BASE=0x80002c10
DMA_CH1_SR_STATE=0x80002c14
DMA_CH1_SR_LEN=0x80002c18
DMA_CH1_SR_BUF=0x80002c1c
# UMAC registers
UMAC_CMD=0x80002408

MODDIR="/lib/modules"
ATTACK="${1:-5}"

devmem_read() {
    local val
    val=$(devmem "$1" 32 2>&1) && echo "$val" || echo "FAIL:$val"
}
devmem_write() { devmem "$1" 32 "$2" 2>&1; }

dump_dma_state() {
    echo "=== DMA Register Dump ==="
    echo "CONTROLLER_CFG : $(devmem_read $DMA_CTRL_CFG)"
    echo "CH_RESET       : $(devmem_read $DMA_CTRL_CH_RESET)"
    echo "CH_DEBUG       : $(devmem_read $DMA_CTRL_CH_DEBUG)"
    echo "GLOB_IRQ_STAT  : $(devmem_read $DMA_GLOB_IRQ_STAT)"
    echo "GLOB_IRQ_MASK  : $(devmem_read $DMA_GLOB_IRQ_MASK)"
    echo "--- RX (CH0) ---"
    echo "CH0_CFG        : $(devmem_read $DMA_CH0_CFG)"
    echo "CH0_INT_STAT   : $(devmem_read $DMA_CH0_INT_STAT)"
    echo "CH0_INT_MASK   : $(devmem_read $DMA_CH0_INT_MASK)"
    echo "CH0_MAX_BURST  : $(devmem_read $DMA_CH0_MAX_BURST)"
    echo "CH0_SR_BASE    : $(devmem_read $DMA_CH0_SR_BASE)"
    echo "CH0_SR_STATE   : $(devmem_read $DMA_CH0_SR_STATE)"
    echo "CH0_SR_LEN     : $(devmem_read $DMA_CH0_SR_LEN)"
    echo "CH0_SR_BUF     : $(devmem_read $DMA_CH0_SR_BUF)"
    echo "--- TX (CH1) ---"
    echo "CH1_CFG        : $(devmem_read $DMA_CH1_CFG)"
    echo "CH1_INT_STAT   : $(devmem_read $DMA_CH1_INT_STAT)"
    echo "CH1_INT_MASK   : $(devmem_read $DMA_CH1_INT_MASK)"
    echo "CH1_MAX_BURST  : $(devmem_read $DMA_CH1_MAX_BURST)"
    echo "CH1_SR_BASE    : $(devmem_read $DMA_CH1_SR_BASE)"
    echo "CH1_SR_STATE   : $(devmem_read $DMA_CH1_SR_STATE)"
    echo "CH1_SR_LEN     : $(devmem_read $DMA_CH1_SR_LEN)"
    echo "CH1_SR_BUF     : $(devmem_read $DMA_CH1_SR_BUF)"
    echo "--- UMAC ---"
    echo "UMAC_CMD       : $(devmem_read $UMAC_CMD)"
    echo "========================="
}

devmem_quiesce() {
    echo "=== Devmem DMA Quiesce ==="

    echo "Step 1: Disable UMAC TX/RX"
    local cmd=$(devmem_read $UMAC_CMD)
    # Clear bits 0 (TX_EN) and 1 (RX_EN)
    local newcmd=$(printf "0x%08X" $(( $(printf "%d" $cmd) & ~3 )))
    devmem_write $UMAC_CMD $newcmd
    echo "  UMAC_CMD: $cmd -> $(devmem_read $UMAC_CMD)"

    echo "Step 2: Halt DMA channels (PKT_HALT | BURST_HALT)"
    devmem_write $DMA_CH0_CFG 0x6
    devmem_write $DMA_CH1_CFG 0x6
    sleep 1

    echo "Step 3: Check halt status"
    echo "  CH0_CFG: $(devmem_read $DMA_CH0_CFG)"
    echo "  CH1_CFG: $(devmem_read $DMA_CH1_CFG)"

    echo "Step 4: Disable channels"
    devmem_write $DMA_CH0_CFG 0x0
    devmem_write $DMA_CH1_CFG 0x0

    echo "Step 5: Disable DMA master"
    devmem_write $DMA_CTRL_CFG 0x0

    echo "Step 6: Channel reset (assert, wait, deassert)"
    devmem_write $DMA_CTRL_CH_RESET 0x3
    sleep 1
    devmem_write $DMA_CTRL_CH_RESET 0x0

    echo "Step 7: Zero state RAM"
    for addr in $DMA_CH0_SR_BASE $DMA_CH0_SR_STATE $DMA_CH0_SR_LEN $DMA_CH0_SR_BUF \
                $DMA_CH1_SR_BASE $DMA_CH1_SR_STATE $DMA_CH1_SR_LEN $DMA_CH1_SR_BUF; do
        devmem_write $addr 0x0
    done

    echo "Step 8: Clear interrupt status"
    devmem_write $DMA_CH0_INT_STAT 0xf
    devmem_write $DMA_CH1_INT_STAT 0xf

    echo "=== Quiesce complete ==="
    dump_dma_state
}

load_enet_only() {
    echo "--- Loading bcm4908_enet only (no DSA) ---"
    insmod $MODDIR/bcm4908_enet.ko 2>&1
    sleep 1
    echo "Interfaces after module load:"
    ip link show 2>/dev/null || ifconfig -a 2>/dev/null || ls /sys/class/net/
}

load_full_stack() {
    echo "--- Loading full DSA stack ---"
    for mod in dsa_core tag_brcm tag_none \
               b53_common b53_srab bcm-sf2 bcm4908_enet; do
        f="$MODDIR/${mod}.ko"
        if [ -f "$f" ]; then
            echo "  insmod $mod"
            insmod "$f" 2>&1 || echo "  WARN: $mod failed"
        fi
    done
    sleep 1
    echo "Interfaces after module load:"
    ip link show 2>/dev/null || ifconfig -a 2>/dev/null || ls /sys/class/net/
}

try_ifup() {
    local iface="${1:-eth0}"
    echo "--- Bringing up $iface (5s timeout) ---"
    # Run ip link set in background with timeout
    ip link set "$iface" up &
    local pid=$!
    local i=0
    while [ $i -lt 50 ]; do
        if ! kill -0 $pid 2>/dev/null; then
            wait $pid
            local rc=$?
            if [ $rc -eq 0 ]; then
                echo "  $iface UP — SUCCESS"
                ip addr show "$iface" 2>/dev/null
                return 0
            else
                echo "  $iface UP — FAILED (rc=$rc)"
                return 1
            fi
        fi
        sleep 0.1
        i=$((i + 1))
    done
    echo "  $iface UP — TIMEOUT (hung)"
    kill $pid 2>/dev/null
    return 1
}

echo "============================================"
echo "=== AP630 Ethernet Test — Attack #$ATTACK ==="
echo "============================================"
echo ""

dump_dma_state
echo ""

case "$ATTACK" in
    1)
        echo ">>> ATTACK 1: Baseline — load full stack, try ifup <<<"
        load_full_stack
        try_ifup eth0
        ;;
    2)
        echo ">>> ATTACK 2: Devmem quiesce, then load full stack <<<"
        devmem_quiesce
        echo ""
        load_full_stack
        try_ifup eth0
        ;;
    3)
        echo ">>> ATTACK 3: Patched driver (quiesce in dma_reset) <<<"
        load_full_stack
        try_ifup eth0
        ;;
    4)
        echo ">>> ATTACK 4: No DSA — enet module only <<<"
        load_enet_only
        # With no DSA, interface might be named differently
        for iface in eth0 bcmenet0; do
            if [ -e "/sys/class/net/$iface" ]; then
                try_ifup "$iface"
                break
            fi
        done
        ;;
    5)
        echo ">>> ATTACK 5: DMA dump only (no module load) <<<"
        echo "Register dump complete. Drop to shell for manual testing."
        ;;
    all)
        for n in 5 2 3 4; do
            echo ""
            echo "========================================"
            echo "=== Running Attack #$n ==="
            echo "========================================"
            # Each attack needs a clean slate — for sequential testing,
            # only #5 and the first real attack are meaningful.
            # After a hang, the system is dead anyway.
            "$0" "$n"
            echo ""
            echo "=== Attack #$n result: $? ==="
            sleep 2
        done
        ;;
    *)
        echo "Unknown attack: $ATTACK"
        echo "Usage: enet-test {1|2|3|4|5|all}"
        ;;
esac

echo ""
echo "=== Kernel log (last 30 lines) ==="
dmesg | tail -30
echo ""
echo "=== TEST COMPLETE ==="
TESTEOF
chmod +x "$WORK_DIR/bin/enet-test"

# Init script
cat > "$WORK_DIR/init" << 'INITEOF'
#!/bin/busybox sh
/bin/busybox --install -s /bin
/bin/busybox --install -s /sbin

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

echo ""
echo "=== AP630 Ethernet Test Boot ==="
uname -a
echo ""
echo "Available attacks:"
echo "  enet-test 5   — DMA register dump only (safe)"
echo "  enet-test 2   — devmem quiesce + load + ifup"
echo "  enet-test 3   — patched driver + load + ifup"
echo "  enet-test 4   — enet only (no DSA) + load + ifup"
echo "  enet-test 1   — baseline (stock behavior) + load + ifup"
echo ""

# Check /dev/mem access
if [ -c /dev/mem ]; then
    echo "/dev/mem: OK"
else
    echo "/dev/mem: MISSING"
    ls -la /dev/mem 2>&1 || true
fi

# Auto-run attack 5 (dump only) on boot
enet-test 5

echo ""
echo "=== TEST BOOT SUCCESSFUL ==="
echo "=== Shell ready — run 'enet-test N' to try attacks ==="
exec /bin/sh
INITEOF
chmod +x "$WORK_DIR/init"

# Build cpio archive
cd "$WORK_DIR"
find . | cpio -o -H newc 2>/dev/null | gzip > /tmp/enet-test-initramfs.cpio.gz

# Wrap for U-Boot
mkimage -A arm64 -T ramdisk -C gzip -n "AP630 enet test initramfs" \
    -d /tmp/enet-test-initramfs.cpio.gz \
    /tmp/enet-test-initramfs.uboot > /dev/null

SIZE=$(stat -c%s /tmp/enet-test-initramfs.uboot | numfmt --to=iec)
echo ""
echo "=== Output ==="
echo "  /tmp/enet-test-initramfs.uboot ($SIZE)"
echo "  Modules: $MOD_COUNT"
echo ""
echo "Stage:  sudo cp /tmp/enet-test-initramfs.uboot /srv/tftp/enet-test-initramfs.uboot"
echo "Boot:   tftp-boot-test.sh -i enet-test-initramfs.uboot -t 180"
