#!/bin/bash
# Fix NetBird nftables to allow K8s NodePort forwarding
# 
# Problem: NetBird's default forward rules only allow ESTABLISHED/RELATED connections,
# blocking NEW TCP connections (like HTTP requests) from NetBird peers.
#
# Solution: Add rules to allow NEW connections from authorized NetBird peers
# in the netbird-rt-fwd chain.
#
# This script should be run on all k8s nodes that need to accept traffic
# via NetBird (typically the control plane node).

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

# Check if nftables is installed
if ! command -v nft &> /dev/null; then
    log_error "nftables (nft) is not installed"
    exit 1
fi

# Check if netbird table exists
if ! nft list table ip netbird &> /dev/null; then
    log_error "NetBird nftables table not found. Is NetBird installed and running?"
    exit 1
fi

log_info "Checking current NetBird forward rules..."

# Get current rules
CURRENT_RULES=$(nft list chain ip netbird netbird-rt-fwd 2>/dev/null || echo "")

if echo "$CURRENT_RULES" | grep -q "ip saddr @nb0000002 accept"; then
    log_warn "Rules already exist. Skipping addition."
    log_info "Current netbird-rt-fwd chain:"
    nft list chain ip netbird netbird-rt-fwd
    exit 0
fi

log_info "Adding forward rules for authorized NetBird peers..."

# Add rules to allow NEW connections from all NetBird peer sets
# These sets are dynamically maintained by NetBird
for set_num in 002 056 058 110; do
    SET_NAME="nb0000${set_num}"
    
    # Check if set exists
    if nft list set ip netbird "$SET_NAME" &> /dev/null; then
        log_info "Adding rule for peer set: $SET_NAME"
        nft add rule ip netbird netbird-rt-fwd ip saddr @"$SET_NAME" accept
    else
        log_warn "Peer set $SET_NAME not found, skipping"
    fi
done

log_info "Rules added successfully!"
log_info "Current netbird-rt-fwd chain:"
nft list chain ip netbird netbird-rt-fwd

# Save rules to make them persistent
log_info "Saving rules to /etc/nftables.d/netbird-k8s.nft for persistence..."
mkdir -p /etc/nftables.d
nft list table ip netbird > /etc/nftables.d/netbird-k8s.nft

# Create systemd service to restore rules on boot
log_info "Creating systemd service for rule persistence..."
cat > /etc/systemd/system/netbird-k8s-rules.service << 'SYSTEMD_EOF'
[Unit]
Description=Restore NetBird K8s forwarding rules
After=netbird.service
Requires=netbird.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/usr/sbin/nft -f /etc/nftables.d/netbird-k8s.nft
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

systemctl daemon-reload
systemctl enable netbird-k8s-rules.service

log_info "${GREEN}✅ NetBird K8s forwarding fix complete!${NC}"
log_info ""
log_info "Summary:"
log_info "  - Added forward rules for NetBird peer connections"
log_info "  - Rules saved to /etc/nftables.d/netbird-k8s.nft"
log_info "  - Systemd service created for persistence across reboots"
log_info ""
log_info "To verify: nft list chain ip netbird netbird-rt-fwd"
