#!/usr/bin/env bash
#
# Configure Dell R730xd PERC H730 controller for JBOD mode via iDRAC racadm
#
# Enables JBOD on the RAID controller and converts all data drives (excluding
# the boot drive in bay 12) to Non-RAID mode so they appear as individual
# block devices to the OS. Required for MergerFS + SnapRAID.
#
# Prerequisites:
#   - sshpass (apt install sshpass)
#   - Network access to iDRAC (see ansible/group_vars/all/network.yml)
#
# Environment variables:
#   IDRAC_PASSWORD  - iDRAC root password (prompted if not set)
#   IDRAC_HOST      - iDRAC IP/hostname (default: from lab-network.env)
#
# Usage:
#   ./scripts/configure-r730xd-jbod.sh [OPTIONS]
#
# Options:
#   --status    Show current disk state and exit
#   --dry-run   Show what would change without applying
#   --force     Allow converting disks that are part of virtual disks
#   --help      Show this help
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source lab network config (see ansible/group_vars/all/network.yml)
# shellcheck source=lab-network.env
[[ -f "${SCRIPT_DIR}/lab-network.env" ]] && . "${SCRIPT_DIR}/lab-network.env"

IDRAC_HOST="${IDRAC_HOST:-${IDRAC_IP:-10.0.0.203}}"
BOOT_DRIVE_BAY="12"
CONTROLLER_FQDD="RAID.Slot.1-1"
ENCLOSURE_FQDD="Enclosure.Internal.0-1:${CONTROLLER_FQDD}"
JOB_POLL_INTERVAL=10
JOB_TIMEOUT=300

# Modes
MODE="apply"  # apply, status, dry-run
FORCE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# Helper functions
# =============================================================================

info()  { echo -e "${GREEN}==> $*${NC}"; }
warn()  { echo -e "${YELLOW}==> WARNING: $*${NC}"; }
error() { echo -e "${RED}==> ERROR: $*${NC}" >&2; }

# Run a racadm command over SSH; strips trailing \r from iDRAC output
racadm() {
    ${IDRAC_SSH} "racadm $*" 2>/dev/null | tr -d '\r'
}

# =============================================================================
# Argument parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --status)
            MODE="status"
            shift
            ;;
        --dry-run)
            MODE="dry-run"
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            head -28 "$0" | tail -21
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            error "Run with --help for usage"
            exit 1
            ;;
    esac
done

# =============================================================================
# Prerequisites
# =============================================================================

if ! command -v sshpass &>/dev/null; then
    error "sshpass is required but not installed. Run: apt install sshpass"
    exit 1
fi

if [[ -z "${IDRAC_PASSWORD:-}" ]]; then
    echo -n "iDRAC password: "
    read -rs IDRAC_PASSWORD
    echo
fi

IDRAC_SSH="sshpass -p ${IDRAC_PASSWORD} ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR root@${IDRAC_HOST}"

# Verify connectivity
info "Connecting to iDRAC at ${IDRAC_HOST}..."
racadm_version="$(${IDRAC_SSH} "racadm getversion" 2>/dev/null | tr -d '\r')" || racadm_version=""
if [[ -z "${racadm_version}" ]]; then
    error "Cannot connect to iDRAC at ${IDRAC_HOST}. Check network and credentials."
    exit 1
fi
info "Connected to iDRAC successfully"

# =============================================================================
# Query physical disks
# =============================================================================

# Parse racadm storage get pdisks -o into structured data.
# Populates parallel arrays indexed by position (0, 1, 2, ...).
# Each disk has: bay number, FQDD, model, serial, size, media type, raid status, bus protocol.

declare -a DISK_BAYS=()
declare -a DISK_FQDDS=()
declare -a DISK_MODELS=()
declare -a DISK_SERIALS=()
declare -a DISK_SIZES=()
declare -a DISK_MEDIA=()
declare -a DISK_RAID_STATUS=()
declare -a DISK_BUS=()

parse_disk_info() {
    local raw_output
    raw_output="$(racadm storage get pdisks -o)"

    local current_fqdd=""
    local current_bay=""
    local current_model=""
    local current_serial=""
    local current_size=""
    local current_media=""
    local current_status=""
    local current_bus=""
    local in_disk=false

    while IFS= read -r line; do
        # Detect disk FQDD line (starts a new disk block)
        if [[ "${line}" =~ Disk\.Bay\.([0-9]+):Enclosure ]]; then
            # Save previous disk if we had one
            if [[ "${in_disk}" == true && -n "${current_bay}" ]]; then
                DISK_BAYS+=("${current_bay}")
                DISK_FQDDS+=("${current_fqdd}")
                DISK_MODELS+=("${current_model}")
                DISK_SERIALS+=("${current_serial}")
                DISK_SIZES+=("${current_size}")
                DISK_MEDIA+=("${current_media}")
                DISK_RAID_STATUS+=("${current_status}")
                DISK_BUS+=("${current_bus}")
            fi
            current_bay="${BASH_REMATCH[1]}"
            current_fqdd="$(echo "${line}" | xargs)"
            current_model=""
            current_serial=""
            current_size=""
            current_media=""
            current_status=""
            current_bus=""
            in_disk=true
        elif [[ "${in_disk}" == true ]]; then
            # Parse key = value lines
            if [[ "${line}" =~ ^[[:space:]]*(ProductId|Model)[[:space:]]*=[[:space:]]*(.*) ]]; then
                current_model="$(echo "${BASH_REMATCH[2]}" | xargs)"
            elif [[ "${line}" =~ ^[[:space:]]*SerialNumber[[:space:]]*=[[:space:]]*(.*) ]]; then
                current_serial="$(echo "${BASH_REMATCH[1]}" | xargs)"
            elif [[ "${line}" =~ ^[[:space:]]*Size[[:space:]]*=[[:space:]]*(.*) ]]; then
                current_size="$(echo "${BASH_REMATCH[1]}" | xargs)"
            elif [[ "${line}" =~ ^[[:space:]]*MediaType[[:space:]]*=[[:space:]]*(.*) ]]; then
                current_media="$(echo "${BASH_REMATCH[1]}" | xargs)"
            elif [[ "${line}" =~ ^[[:space:]]*RaidStatus[[:space:]]*=[[:space:]]*(.*) ]]; then
                current_status="$(echo "${BASH_REMATCH[1]}" | xargs)"
            elif [[ "${line}" =~ ^[[:space:]]*BusProtocol[[:space:]]*=[[:space:]]*(.*) ]]; then
                current_bus="$(echo "${BASH_REMATCH[1]}" | xargs)"
            fi
        fi
    done <<< "${raw_output}"

    # Save the last disk
    if [[ "${in_disk}" == true && -n "${current_bay}" ]]; then
        DISK_BAYS+=("${current_bay}")
        DISK_FQDDS+=("${current_fqdd}")
        DISK_MODELS+=("${current_model}")
        DISK_SERIALS+=("${current_serial}")
        DISK_SIZES+=("${current_size}")
        DISK_MEDIA+=("${current_media}")
        DISK_RAID_STATUS+=("${current_status}")
        DISK_BUS+=("${current_bus}")
    fi
}

print_disk_table() {
    local label="${1:-Physical Disks}"
    echo ""
    echo -e "${BOLD}${label}${NC}"
    printf "%-6s %-44s %-20s %-10s %-10s %-12s\n" \
        "Bay" "FQDD" "Model" "Size" "Media" "RAID Status"
    printf "%-6s %-44s %-20s %-10s %-10s %-12s\n" \
        "---" "----" "-----" "----" "-----" "-----------"

    for i in "${!DISK_BAYS[@]}"; do
        local bay="${DISK_BAYS[${i}]}"
        local fqdd="${DISK_FQDDS[${i}]}"
        local model="${DISK_MODELS[${i}]}"
        local size="${DISK_SIZES[${i}]}"
        local media="${DISK_MEDIA[${i}]}"
        local status="${DISK_RAID_STATUS[${i}]}"

        # Highlight boot drive and Non-RAID status
        local bay_display="${bay}"
        local status_display="${status}"
        if [[ "${bay}" == "${BOOT_DRIVE_BAY}" ]]; then
            bay_display="${CYAN}${bay} *${NC}"
            status_display="${CYAN}${status}${NC}"
        elif [[ "${status}" == "Non-RAID" ]]; then
            status_display="${GREEN}${status}${NC}"
        elif [[ "${status}" == "Online" ]]; then
            status_display="${YELLOW}${status}${NC}"
        fi

        printf "%-6b %-44s %-20s %-10s %-10s %-12b\n" \
            "${bay_display}" "${fqdd}" "${model:0:20}" "${size}" "${media}" "${status_display}"
    done

    echo ""
    echo -e "  ${CYAN}*${NC} = Boot drive (bay ${BOOT_DRIVE_BAY}, excluded from operations)"
}

# =============================================================================
# Main logic
# =============================================================================

info "Querying physical disks from PERC H730..."
parse_disk_info

if [[ ${#DISK_BAYS[@]} -eq 0 ]]; then
    warn "No physical disks found. Are drives installed?"
    exit 0
fi

print_disk_table "Current Disk State"

# --status: just display and exit
if [[ "${MODE}" == "status" ]]; then
    exit 0
fi

# =============================================================================
# Check JBOD mode on controller
# =============================================================================

info "Checking JBOD mode on controller ${CONTROLLER_FQDD}..."
jbod_output="$(racadm get "storage.controller.${CONTROLLER_FQDD}.EnableJBOD")"

if echo "${jbod_output}" | grep -qi "enabled"; then
    info "JBOD mode is already enabled"
    JBOD_NEEDS_ENABLE=false
elif echo "${jbod_output}" | grep -qi "disabled"; then
    warn "JBOD mode is currently disabled"
    JBOD_NEEDS_ENABLE=true
else
    # Some firmware versions don't support the EnableJBOD attribute —
    # they may use converttonon-raid directly without needing this toggle
    warn "Could not determine JBOD mode status (may not be supported on this firmware)"
    warn "Raw output: ${jbod_output}"
    JBOD_NEEDS_ENABLE=false
fi

# =============================================================================
# Identify target disks (non-boot, needing conversion)
# =============================================================================

declare -a TARGET_INDICES=()
declare -a SKIP_ALREADY=()
declare -a SKIP_ONLINE=()

for i in "${!DISK_BAYS[@]}"; do
    bay="${DISK_BAYS[${i}]}"
    status="${DISK_RAID_STATUS[${i}]}"

    # Always skip boot drive
    if [[ "${bay}" == "${BOOT_DRIVE_BAY}" ]]; then
        info "Skipping bay ${bay} (boot drive: ${DISK_MODELS[${i}]} ${DISK_SERIALS[${i}]})"
        continue
    fi

    if [[ "${status}" == "Non-RAID" ]]; then
        SKIP_ALREADY+=("${i}")
    elif [[ "${status}" == "Online" ]]; then
        # Disk is part of a virtual disk
        if [[ "${FORCE}" == true ]]; then
            TARGET_INDICES+=("${i}")
        else
            SKIP_ONLINE+=("${i}")
        fi
    else
        # "Ready" or other states eligible for conversion
        TARGET_INDICES+=("${i}")
    fi
done

# Report skipped disks
for i in "${SKIP_ALREADY[@]+"${SKIP_ALREADY[@]}"}"; do
    info "Bay ${DISK_BAYS[${i}]} already Non-RAID — skipping"
done

for i in "${SKIP_ONLINE[@]+"${SKIP_ONLINE[@]}"}"; do
    warn "Bay ${DISK_BAYS[${i}]} is Online (part of virtual disk) — skipping (use --force to override)"
done

if [[ ${#TARGET_INDICES[@]} -eq 0 && "${JBOD_NEEDS_ENABLE}" == false ]]; then
    info "All data drives are already in Non-RAID mode. Nothing to do."
    exit 0
fi

# =============================================================================
# Dry-run: show what would happen
# =============================================================================

if [[ "${MODE}" == "dry-run" ]]; then
    echo ""
    echo -e "${BOLD}Dry Run — Changes that would be applied:${NC}"
    echo ""

    if [[ "${JBOD_NEEDS_ENABLE}" == true ]]; then
        echo "  1. Enable JBOD mode on controller ${CONTROLLER_FQDD}"
    fi

    local_step=1
    if [[ "${JBOD_NEEDS_ENABLE}" == true ]]; then
        local_step=2
    fi

    for i in "${TARGET_INDICES[@]+"${TARGET_INDICES[@]}"}"; do
        echo "  ${local_step}. Convert bay ${DISK_BAYS[${i}]} to Non-RAID (${DISK_MODELS[${i}]} ${DISK_SIZES[${i}]})"
        ((local_step++))
    done

    if [[ ${#TARGET_INDICES[@]} -gt 0 || "${JBOD_NEEDS_ENABLE}" == true ]]; then
        echo "  ${local_step}. Create realtime job on ${CONTROLLER_FQDD} to apply changes"
    fi

    echo ""
    info "Dry run complete. Run without --dry-run to apply."
    exit 0
fi

# =============================================================================
# Apply changes
# =============================================================================

CHANGES_MADE=false

# Enable JBOD if needed
if [[ "${JBOD_NEEDS_ENABLE}" == true ]]; then
    info "Enabling JBOD mode on ${CONTROLLER_FQDD}..."
    result="$(racadm set "storage.controller.${CONTROLLER_FQDD}.EnableJBOD" Enabled)"
    if echo "${result}" | grep -qi "success\|successfully"; then
        info "JBOD mode enable requested"
        CHANGES_MADE=true
    else
        error "Failed to enable JBOD mode"
        error "Output: ${result}"
        exit 1
    fi
fi

# Convert each target disk
for i in "${TARGET_INDICES[@]+"${TARGET_INDICES[@]}"}"; do
    bay="${DISK_BAYS[${i}]}"
    fqdd="Disk.Bay.${bay}:${ENCLOSURE_FQDD}"

    info "Converting bay ${bay} to Non-RAID (${DISK_MODELS[${i}]} ${DISK_SIZES[${i}]})..."
    result="$(racadm "storage converttonon-raid:${fqdd}")"

    if echo "${result}" | grep -qi "success\|successfully\|completed"; then
        info "Bay ${bay} conversion requested"
        CHANGES_MADE=true
    else
        error "Failed to convert bay ${bay}"
        error "Output: ${result}"
        exit 1
    fi
done

# Create job if changes were made
if [[ "${CHANGES_MADE}" == false ]]; then
    info "No changes needed."
    exit 0
fi

info "Creating realtime job on ${CONTROLLER_FQDD}..."
job_output="$(racadm "jobqueue create ${CONTROLLER_FQDD} --realtime")"

# Extract job ID from output (format: JID_XXXXXXXXX)
JOB_ID="$(echo "${job_output}" | grep -oP 'JID_\d+' || true)"

if [[ -z "${JOB_ID}" ]]; then
    # Realtime job may not be supported — try without --realtime
    warn "Realtime job creation may not be supported, trying standard job..."
    job_output="$(racadm "jobqueue create ${CONTROLLER_FQDD}")"
    JOB_ID="$(echo "${job_output}" | grep -oP 'JID_\d+' || true)"

    if [[ -z "${JOB_ID}" ]]; then
        error "Failed to create job"
        error "Output: ${job_output}"
        error "You may need to reboot the server for changes to take effect:"
        error "  racadm serveraction powercycle"
        exit 1
    fi

    warn "Standard job created (${JOB_ID}). A server reboot may be required:"
    warn "  sshpass -p '\${IDRAC_PASSWORD}' ssh root@${IDRAC_HOST} 'racadm serveraction powercycle'"
    warn "Run --status after reboot to verify."
    exit 0
fi

info "Job ${JOB_ID} created. Waiting for completion..."

# =============================================================================
# Wait for job completion
# =============================================================================

elapsed=0
while [[ ${elapsed} -lt ${JOB_TIMEOUT} ]]; do
    job_status="$(racadm "jobqueue view -i ${JOB_ID}")"

    if echo "${job_status}" | grep -qi "Status=Completed"; then
        info "Job ${JOB_ID} completed successfully"
        break
    elif echo "${job_status}" | grep -qi "Status=Failed"; then
        error "Job ${JOB_ID} failed"
        error_detail="$(echo "${job_status}" | grep -i "message\|status" || true)"
        error "${error_detail}"
        exit 1
    fi

    sleep "${JOB_POLL_INTERVAL}"
    elapsed=$((elapsed + JOB_POLL_INTERVAL))
    echo -ne "\r  Waiting... ${elapsed}s / ${JOB_TIMEOUT}s"
done
echo ""

if [[ ${elapsed} -ge ${JOB_TIMEOUT} ]]; then
    error "Job ${JOB_ID} timed out after ${JOB_TIMEOUT}s"
    error "Check status manually: racadm jobqueue view -i ${JOB_ID}"
    exit 1
fi

# =============================================================================
# Final report
# =============================================================================

info "Re-querying disk state..."

# Reset arrays
DISK_BAYS=()
DISK_FQDDS=()
DISK_MODELS=()
DISK_SERIALS=()
DISK_SIZES=()
DISK_MEDIA=()
DISK_RAID_STATUS=()
DISK_BUS=()

parse_disk_info
print_disk_table "Final Disk State"

# Verify all target bays are now Non-RAID
all_good=true
for i in "${!DISK_BAYS[@]}"; do
    bay="${DISK_BAYS[${i}]}"
    status="${DISK_RAID_STATUS[${i}]}"

    if [[ "${bay}" != "${BOOT_DRIVE_BAY}" && "${status}" != "Non-RAID" ]]; then
        warn "Bay ${bay} is still '${status}' — may need a reboot to apply"
        all_good=false
    fi
done

if [[ "${all_good}" == true ]]; then
    info "All data drives are in Non-RAID mode. Drives should now be visible to the OS."
    info "Verify on the host with: ssh r730xd 'lsblk'"
else
    warn "Some drives may need a server reboot to finalize conversion."
    warn "Reboot via iDRAC: racadm serveraction powercycle"
    warn "Then re-run: $0 --status"
fi
