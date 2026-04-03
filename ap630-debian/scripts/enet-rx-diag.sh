#!/bin/bash
# AP630 Ethernet RX Bandwidth Diagnostic
#
# Tests whether the ~10 Mbps RX ceiling is packet-rate or byte-rate limited,
# and probes DMA register tuning parameters that the mainline driver never sets.
#
# Run on the AP630 (Debian rootfs). Requires:
#   - iperf3 server running on the test host (default: gateway)
#   - devmem (busybox applet or devmem2 package)
#   - iperf3 installed in rootfs
#
# Usage:
#   enet-rx-diag.sh [iperf3-server-ip]

set -euo pipefail

IPERF_HOST="${1:-}"
DURATION=10  # seconds per iperf test

# === Register addresses ===
# ENET block base: 0x80002000
ENET_CONTROL=0x80002000
ENET_MIB_CTRL=0x80002004
ENET_RX_ERR_MASK=0x80002008
ENET_MIB_MAX_PKT=0x8000200c
ENET_ENABLE_DROP=0x80002020
ENET_IRQ_ENABLE=0x80002024
ENET_GMAC_STATUS=0x80002028
ENET_IRQ_STATUS=0x8000202c
ENET_OVERFLOW_CTR=0x80002030
ENET_FLUSH=0x80002034
ENET_BP_FORCE=0x8000203c
ENET_OK_TO_SEND=0x80002040   # Never set by driver!
ENET_TX_CRC_CTRL=0x80002044

# UMAC
UMAC_CMD=0x80002408

# DMA controller
DMA_CTRL_CFG=0x80002800
DMA_FLOWCTL_CH1_LO=0x80002804
DMA_FLOWCTL_CH1_HI=0x80002808
DMA_FLOWCTL_CH1_ALLOC=0x8000280c
DMA_FLOWCTL_CH3_LO=0x80002810
DMA_FLOWCTL_CH3_HI=0x80002814
DMA_CTRL_CH_RESET=0x80002834
DMA_CTRL_CH_DEBUG=0x80002838
DMA_GLOB_IRQ_STAT=0x80002840
DMA_GLOB_IRQ_MASK=0x80002844

# DMA RX channel (CH0)
DMA_CH0_CFG=0x80002a00
DMA_CH0_INT_STAT=0x80002a04
DMA_CH0_INT_MASK=0x80002a08
DMA_CH0_MAX_BURST=0x80002a0c

# DMA TX channel (CH1)
DMA_CH1_CFG=0x80002a10
DMA_CH1_INT_STAT=0x80002a14
DMA_CH1_INT_MASK=0x80002a18
DMA_CH1_MAX_BURST=0x80002a1c

# State RAM
DMA_CH0_SR_BASE=0x80002c00
DMA_CH0_SR_STATE=0x80002c04
DMA_CH0_SR_LEN=0x80002c08
DMA_CH0_SR_BUF=0x80002c0c
DMA_CH1_SR_BASE=0x80002c10
DMA_CH1_SR_STATE=0x80002c14
DMA_CH1_SR_LEN=0x80002c18
DMA_CH1_SR_BUF=0x80002c1c

# === Helpers ===

dr() { devmem "$1" 32 2>/dev/null || echo "FAIL"; }
dw() { devmem "$1" 32 "$2" 2>/dev/null; }

log() { echo "[$(date +%H:%M:%S)] $*"; }

check_prereqs() {
    local missing=0
    if ! command -v devmem >/dev/null 2>&1; then
        echo "FAIL: devmem not found"
        missing=1
    fi
    if ! command -v iperf3 >/dev/null 2>&1; then
        echo "FAIL: iperf3 not found"
        missing=1
    fi
    if [[ -z "$IPERF_HOST" ]]; then
        # Auto-detect gateway
        IPERF_HOST=$(ip route show default | awk '/default/{print $3}' | head -1)
        if [[ -z "$IPERF_HOST" ]]; then
            echo "FAIL: no iperf3 server IP and no default gateway"
            missing=1
        else
            log "Auto-detected iperf3 host: $IPERF_HOST"
        fi
    fi
    [[ $missing -eq 0 ]] || exit 1
}

# === Phase 1: Full register dump ===

phase1_register_dump() {
    log "=== PHASE 1: Register Dump ==="

    echo "ENET block:"
    echo "  CONTROL       : $(dr $ENET_CONTROL)"
    echo "  MIB_CTRL      : $(dr $ENET_MIB_CTRL)"
    echo "  RX_ERR_MASK   : $(dr $ENET_RX_ERR_MASK)"
    echo "  MIB_MAX_PKT   : $(dr $ENET_MIB_MAX_PKT)"
    echo "  ENABLE_DROP   : $(dr $ENET_ENABLE_DROP)"
    echo "  IRQ_ENABLE    : $(dr $ENET_IRQ_ENABLE)"
    echo "  GMAC_STATUS   : $(dr $ENET_GMAC_STATUS)"
    echo "  IRQ_STATUS    : $(dr $ENET_IRQ_STATUS)"
    echo "  OVERFLOW_CTR  : $(dr $ENET_OVERFLOW_CTR)"
    echo "  FLUSH         : $(dr $ENET_FLUSH)"
    echo "  BP_FORCE      : $(dr $ENET_BP_FORCE)"
    echo "  OK_TO_SEND    : $(dr $ENET_OK_TO_SEND)"
    echo "  TX_CRC_CTRL   : $(dr $ENET_TX_CRC_CTRL)"

    echo ""
    echo "UMAC:"
    echo "  CMD           : $(dr $UMAC_CMD)"

    echo ""
    echo "DMA controller:"
    echo "  CTRL_CFG      : $(dr $DMA_CTRL_CFG)"
    echo "  FLOWCTL_CH1_LO: $(dr $DMA_FLOWCTL_CH1_LO)"
    echo "  FLOWCTL_CH1_HI: $(dr $DMA_FLOWCTL_CH1_HI)"
    echo "  FLOWCTL_CH1_AL: $(dr $DMA_FLOWCTL_CH1_ALLOC)"
    echo "  FLOWCTL_CH3_LO: $(dr $DMA_FLOWCTL_CH3_LO)"
    echo "  FLOWCTL_CH3_HI: $(dr $DMA_FLOWCTL_CH3_HI)"
    echo "  CH_RESET      : $(dr $DMA_CTRL_CH_RESET)"
    echo "  CH_DEBUG      : $(dr $DMA_CTRL_CH_DEBUG)"
    echo "  GLOB_IRQ_STAT : $(dr $DMA_GLOB_IRQ_STAT)"
    echo "  GLOB_IRQ_MASK : $(dr $DMA_GLOB_IRQ_MASK)"

    echo ""
    echo "DMA CH0 (RX):"
    echo "  CFG           : $(dr $DMA_CH0_CFG)"
    echo "  INT_STAT      : $(dr $DMA_CH0_INT_STAT)"
    echo "  INT_MASK      : $(dr $DMA_CH0_INT_MASK)"
    echo "  MAX_BURST     : $(dr $DMA_CH0_MAX_BURST)"
    echo "  SR_BASE       : $(dr $DMA_CH0_SR_BASE)"
    echo "  SR_STATE      : $(dr $DMA_CH0_SR_STATE)"
    echo "  SR_LEN        : $(dr $DMA_CH0_SR_LEN)"
    echo "  SR_BUF        : $(dr $DMA_CH0_SR_BUF)"

    echo ""
    echo "DMA CH1 (TX):"
    echo "  CFG           : $(dr $DMA_CH1_CFG)"
    echo "  INT_STAT      : $(dr $DMA_CH1_INT_STAT)"
    echo "  INT_MASK      : $(dr $DMA_CH1_INT_MASK)"
    echo "  MAX_BURST     : $(dr $DMA_CH1_MAX_BURST)"
    echo "  SR_BASE       : $(dr $DMA_CH1_SR_BASE)"
    echo "  SR_STATE      : $(dr $DMA_CH1_SR_STATE)"
    echo "  SR_LEN        : $(dr $DMA_CH1_SR_LEN)"
    echo "  SR_BUF        : $(dr $DMA_CH1_SR_BUF)"

    echo ""
    echo "Interrupt counts:"
    grep -E "enet|bcm4908" /proc/interrupts 2>/dev/null || echo "  (no enet interrupts found)"

    echo ""
    echo "Interface stats:"
    ip -s link show eth0 2>/dev/null || echo "  (eth0 not found)"
}

# === Phase 2: Packet-rate vs byte-rate characterization ===

run_iperf_rx() {
    local label="$1"
    shift
    log "  RX test: $label"
    # -R = reverse (server sends to us = RX test)
    local result
    result=$(iperf3 -c "$IPERF_HOST" -R -t "$DURATION" "$@" --json 2>/dev/null) || {
        echo "    FAIL: iperf3 failed"
        return 1
    }
    # Extract receiver (our) results
    local bits bps pps
    bits=$(echo "$result" | grep -o '"bits_per_second":[0-9.]*' | tail -1 | cut -d: -f2)
    echo "    ${bits:-0} bps ($(echo "${bits:-0}" | awk '{printf "%.1f Mbps", $1/1e6}'))"
}

run_iperf_udp_rx() {
    local label="$1"
    local pktsize="$2"
    shift 2
    log "  UDP RX ($pktsize byte): $label"
    local result
    result=$(iperf3 -c "$IPERF_HOST" -R -u -t "$DURATION" -l "$pktsize" -b 1G "$@" --json 2>/dev/null) || {
        echo "    FAIL: iperf3 failed"
        return 1
    }
    local bits packets lost
    bits=$(echo "$result" | grep -o '"bits_per_second":[0-9.]*' | tail -1 | cut -d: -f2)
    packets=$(echo "$result" | grep -o '"packets":[0-9]*' | tail -1 | cut -d: -f2)
    lost=$(echo "$result" | grep -o '"lost_packets":[0-9]*' | tail -1 | cut -d: -f2)
    echo "    $(echo "${bits:-0}" | awk '{printf "%.1f Mbps", $1/1e6}'), ${packets:-?} pkts rcvd, ${lost:-?} lost"
}

phase2_bandwidth_characterization() {
    log "=== PHASE 2: Bandwidth Characterization ==="
    log "iperf3 server: $IPERF_HOST, duration: ${DURATION}s per test"

    echo ""
    echo "--- TCP RX (baseline) ---"
    run_iperf_rx "TCP default"

    echo ""
    echo "--- UDP RX packet-size sweep (determines packet-rate vs byte-rate) ---"
    for size in 64 128 256 512 1024 1400; do
        run_iperf_udp_rx "sweep" "$size"
    done

    echo ""
    echo "--- TCP TX (baseline, for comparison) ---"
    log "  TX test: TCP default"
    iperf3 -c "$IPERF_HOST" -t "$DURATION" --json 2>/dev/null | \
        grep -o '"bits_per_second":[0-9.]*' | tail -1 | \
        awk -F: '{printf "    %s bps (%.1f Mbps)\n", $2, $2/1e6}'

    echo ""
    echo "--- UDP TX (baseline) ---"
    log "  TX test: UDP 1400 byte"
    iperf3 -c "$IPERF_HOST" -u -t "$DURATION" -l 1400 -b 1G --json 2>/dev/null | \
        grep -o '"bits_per_second":[0-9.]*' | tail -1 | \
        awk -F: '{printf "    %s bps (%.1f Mbps)\n", $2, $2/1e6}'

    echo ""
    echo "--- Interrupt count during idle ---"
    local irq_before irq_after
    irq_before=$(grep -E "enet|bcm4908" /proc/interrupts 2>/dev/null | awk '{sum+=$2}END{print sum+0}')
    sleep 2
    irq_after=$(grep -E "enet|bcm4908" /proc/interrupts 2>/dev/null | awk '{sum+=$2}END{print sum+0}')
    echo "    IRQs in 2s idle: $((irq_after - irq_before))"

    echo ""
    echo "--- Interrupt count during RX load ---"
    irq_before=$(grep -E "enet|bcm4908" /proc/interrupts 2>/dev/null | awk '{sum+=$2}END{print sum+0}')
    iperf3 -c "$IPERF_HOST" -R -t 5 >/dev/null 2>&1 &
    local iperf_pid=$!
    sleep 5
    wait "$iperf_pid" 2>/dev/null || true
    irq_after=$(grep -E "enet|bcm4908" /proc/interrupts 2>/dev/null | awk '{sum+=$2}END{print sum+0}')
    echo "    IRQs in 5s RX load: $((irq_after - irq_before))"
}

# === Phase 3: Register tuning experiments ===
#
# These modify DMA registers at runtime via devmem. The interface must be
# brought down and up around changes that affect active DMA state.
# Some registers (like OK_TO_SEND) may be safe to write while running.

phase3_tuning_experiments() {
    log "=== PHASE 3: Register Tuning Experiments ==="

    echo ""
    echo "--- Experiment 1: Read OK_TO_SEND default ---"
    local ots_val
    ots_val=$(dr $ENET_OK_TO_SEND)
    echo "  ENET_DMA_RX_OK_TO_SEND_COUNT = $ots_val (mask 0xf)"
    echo "  (If 0, switch may throttle packets to DMA)"

    echo ""
    echo "--- Experiment 2: Set OK_TO_SEND = 0xF (max=15) while running ---"
    dw $ENET_OK_TO_SEND 0xF
    echo "  OK_TO_SEND after write: $(dr $ENET_OK_TO_SEND)"
    echo "  Running RX test with OK_TO_SEND=15..."
    run_iperf_rx "OK_TO_SEND=15"
    echo "  Restoring OK_TO_SEND to original: $ots_val"
    dw $ENET_OK_TO_SEND "$ots_val"

    echo ""
    echo "--- Experiment 3: Increase RX burst length ---"
    local burst_val
    burst_val=$(dr $DMA_CH0_MAX_BURST)
    echo "  Current CH0_MAX_BURST = $burst_val"

    for burst in 16 32 64 128; do
        echo "  Testing burst=$burst..."
        ip link set eth0 down 2>/dev/null
        sleep 0.2
        dw $DMA_CH0_MAX_BURST "$burst"
        ip link set eth0 up 2>/dev/null
        sleep 2  # wait for link + DHCP
        echo "    CH0_MAX_BURST after write: $(dr $DMA_CH0_MAX_BURST)"
        run_iperf_rx "burst=$burst" || echo "    (test failed, link may not be up)"
    done
    # Restore
    ip link set eth0 down 2>/dev/null
    sleep 0.2
    dw $DMA_CH0_MAX_BURST "$burst_val"
    ip link set eth0 up 2>/dev/null
    sleep 2

    echo ""
    echo "--- Experiment 4: Enable flow control + set thresholds ---"
    local ctrl_val
    ctrl_val=$(dr $DMA_CTRL_CFG)
    echo "  Current CTRL_CFG = $ctrl_val"

    # Set flow control thresholds (1/3 and 2/3 of 200 descriptors, like bcm63xx)
    echo "  Setting flow control: lo=66, hi=133, enable FLOWC_CH1"
    ip link set eth0 down 2>/dev/null
    sleep 0.2
    dw $DMA_FLOWCTL_CH1_LO 0x42    # 66
    dw $DMA_FLOWCTL_CH1_HI 0x85    # 133
    # Enable flow control bit (bit 1 of CTRL_CFG)
    local new_ctrl
    new_ctrl=$(printf "0x%08X" $(( $(printf "%d" "$ctrl_val") | 2 )))
    dw $DMA_CTRL_CFG "$new_ctrl"
    ip link set eth0 up 2>/dev/null
    sleep 2
    echo "  CTRL_CFG after: $(dr $DMA_CTRL_CFG)"
    echo "  FLOWCTL_CH1_LO: $(dr $DMA_FLOWCTL_CH1_LO)"
    echo "  FLOWCTL_CH1_HI: $(dr $DMA_FLOWCTL_CH1_HI)"
    run_iperf_rx "flow_ctrl=on" || echo "    (test failed)"

    # Restore
    ip link set eth0 down 2>/dev/null
    sleep 0.2
    dw $DMA_CTRL_CFG "$ctrl_val"
    dw $DMA_FLOWCTL_CH1_LO 0x0
    dw $DMA_FLOWCTL_CH1_HI 0x0
    ip link set eth0 up 2>/dev/null
    sleep 2

    echo ""
    echo "--- Experiment 5: Combined (OK_TO_SEND=15 + burst=16 + flow_ctrl) ---"
    ip link set eth0 down 2>/dev/null
    sleep 0.2
    dw $ENET_OK_TO_SEND 0xF
    dw $DMA_CH0_MAX_BURST 0x10
    dw $DMA_FLOWCTL_CH1_LO 0x42
    dw $DMA_FLOWCTL_CH1_HI 0x85
    new_ctrl=$(printf "0x%08X" $(( $(printf "%d" "$ctrl_val") | 2 )))
    dw $DMA_CTRL_CFG "$new_ctrl"
    ip link set eth0 up 2>/dev/null
    sleep 2
    echo "  OK_TO_SEND : $(dr $ENET_OK_TO_SEND)"
    echo "  CH0_BURST  : $(dr $DMA_CH0_MAX_BURST)"
    echo "  CTRL_CFG   : $(dr $DMA_CTRL_CFG)"
    run_iperf_rx "combined"

    # Restore everything
    ip link set eth0 down 2>/dev/null
    sleep 0.2
    dw $ENET_OK_TO_SEND "$ots_val"
    dw $DMA_CH0_MAX_BURST "$burst_val"
    dw $DMA_CTRL_CFG "$ctrl_val"
    dw $DMA_FLOWCTL_CH1_LO 0x0
    dw $DMA_FLOWCTL_CH1_HI 0x0
    ip link set eth0 up 2>/dev/null
    sleep 2

    echo ""
    echo "--- Experiment 6: Check OVERFLOW_COUNTER and DROP_PKT ---"
    echo "  Before RX load:"
    echo "    OVERFLOW_CTR : $(dr $ENET_OVERFLOW_CTR)"
    echo "    ENABLE_DROP  : $(dr $ENET_ENABLE_DROP)"
    echo "    IRQ_STATUS   : $(dr $ENET_IRQ_STATUS)"
    iperf3 -c "$IPERF_HOST" -R -t 5 >/dev/null 2>&1
    echo "  After 5s RX load:"
    echo "    OVERFLOW_CTR : $(dr $ENET_OVERFLOW_CTR)"
    echo "    IRQ_STATUS   : $(dr $ENET_IRQ_STATUS)"
}

# === Main ===

log "AP630 Ethernet RX Bandwidth Diagnostic"
log "======================================="
echo ""

check_prereqs

phase1_register_dump
echo ""
phase2_bandwidth_characterization
echo ""
phase3_tuning_experiments

echo ""
log "=== DIAGNOSTIC COMPLETE ==="
log "Key questions answered:"
log "  1. Register dump shows current DMA config (especially OK_TO_SEND, burst, flow ctrl)"
log "  2. Packet-size sweep shows if limit is packet-rate or byte-rate"
log "  3. Tuning experiments show if any register changes improve throughput"
