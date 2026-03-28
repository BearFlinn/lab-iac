#!/usr/bin/env bash
#
# Query Dell R730xd drive bay information via iDRAC racadm
#
# Outputs JSON array of physical disk info, one object per drive bay.
# Designed to be consumed by Ansible for bay→serial→device resolution.
#
# Prerequisites:
#   - sshpass (apt install sshpass)
#   - Network access to iDRAC
#
# Environment variables:
#   IDRAC_PASSWORD  - iDRAC root password (required)
#   IDRAC_HOST      - iDRAC IP/hostname (default: 10.0.0.203)
#   BOOT_DRIVE_BAY  - Bay to exclude from output (default: 12)
#
# Usage:
#   IDRAC_PASSWORD=secret ./scripts/query-r730xd-bays.sh
#
# Output:
#   [{"bay":0,"serial":"WD-WMAZ12345","model":"WDC WD40EFRX","size":"3.637 TB","media":"HDD"}, ...]

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

IDRAC_HOST="${IDRAC_HOST:-10.0.0.203}"
BOOT_DRIVE_BAY="${BOOT_DRIVE_BAY:-12}"

# =============================================================================
# Prerequisites
# =============================================================================

if ! command -v sshpass &>/dev/null; then
    echo '{"error": "sshpass is required but not installed"}' >&2
    exit 1
fi

if [[ -z "${IDRAC_PASSWORD:-}" ]]; then
    echo '{"error": "IDRAC_PASSWORD environment variable is required"}' >&2
    exit 1
fi

IDRAC_SSH="sshpass -p ${IDRAC_PASSWORD} ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR root@${IDRAC_HOST}"

# =============================================================================
# Query iDRAC
# =============================================================================

# Run racadm command, strip trailing \r
racadm_output=$(${IDRAC_SSH} "racadm storage get pdisks -o" 2>/dev/null | tr -d '\r') || {
    echo '{"error": "Failed to connect to iDRAC or query disks"}' >&2
    exit 1
}

# =============================================================================
# Parse into JSON
# =============================================================================

# Build JSON array by parsing racadm output line by line
json_entries=()
current_bay=""
current_serial=""
current_model=""
current_size=""
current_media=""
in_disk=false

flush_disk() {
    if [[ "${in_disk}" == true && -n "${current_bay}" ]]; then
        # Skip boot drive bay
        if [[ "${current_bay}" != "${BOOT_DRIVE_BAY}" ]]; then
            # Escape strings for JSON safety
            json_entries+=("{\"bay\":${current_bay},\"serial\":\"${current_serial}\",\"model\":\"${current_model}\",\"size\":\"${current_size}\",\"media\":\"${current_media}\"}")
        fi
    fi
}

while IFS= read -r line; do
    # Detect disk FQDD line (starts a new disk block)
    if [[ "${line}" =~ Disk\.Bay\.([0-9]+):Enclosure ]]; then
        flush_disk
        current_bay="${BASH_REMATCH[1]}"
        current_serial=""
        current_model=""
        current_size=""
        current_media=""
        in_disk=true
    elif [[ "${in_disk}" == true ]]; then
        if [[ "${line}" =~ ^[[:space:]]*(ProductId|Model)[[:space:]]*=[[:space:]]*(.*) ]]; then
            current_model="$(echo "${BASH_REMATCH[2]}" | xargs)"
        elif [[ "${line}" =~ ^[[:space:]]*SerialNumber[[:space:]]*=[[:space:]]*(.*) ]]; then
            current_serial="$(echo "${BASH_REMATCH[1]}" | xargs)"
        elif [[ "${line}" =~ ^[[:space:]]*Size[[:space:]]*=[[:space:]]*(.*) ]]; then
            current_size="$(echo "${BASH_REMATCH[1]}" | xargs)"
        elif [[ "${line}" =~ ^[[:space:]]*MediaType[[:space:]]*=[[:space:]]*(.*) ]]; then
            current_media="$(echo "${BASH_REMATCH[1]}" | xargs)"
        fi
    fi
done <<< "${racadm_output}"

# Flush last disk
flush_disk

# Output as JSON array
if [[ ${#json_entries[@]} -eq 0 ]]; then
    echo "[]"
else
    echo "[$(IFS=,; echo "${json_entries[*]}")]"
fi
