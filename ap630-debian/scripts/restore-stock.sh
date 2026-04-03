#!/bin/bash
# Restore AP630 to stock HiveOS firmware via U-Boot + TFTP
# Follows the procedure in RESTORE-STOCK.md
set -euo pipefail

SERIAL_DEV="/dev/ttyUSB0"
BAUD=9600
UBOOT_PW="AhNf?d@ta06"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TFTP_DIR="/srv/tftp"

# Verify backup files exist on TFTP server
for f in mtd4_kernel.bin mtd5_dts.bin mtd6_appimage.bin; do
    if [[ ! -f "$TFTP_DIR/$f" ]]; then
        echo "MISSING: $TFTP_DIR/$f" >&2
        exit 1
    fi
done
echo "Backup files verified on TFTP server"

# Kill anything holding the serial port
sudo fuser -k "$SERIAL_DEV" 2>/dev/null || true
sleep 1

echo "PoE cycling AP and catching U-Boot prompt..."
python3 "$SCRIPT_DIR/catch-uboot.py" --poe
if [[ $? -ne 0 ]]; then
    echo "Failed to reach U-Boot prompt" >&2
    exit 1
fi

echo ""
echo "=== At U-Boot prompt — starting restore ==="
echo ""

# Function to send a U-Boot command and wait for prompt
send_uboot() {
    local cmd="$1"
    local timeout="${2:-120}"
    echo ">>> $cmd"
    # Send command, wait for u-boot> prompt
    expect -f <(cat <<EXPECT
set timeout $timeout
log_user 1
spawn -noecho -open [open $SERIAL_DEV r+]
# Configure serial - already set by catch-uboot.py
send "$cmd\r"
expect {
    "u-boot>" { }
    timeout {
        puts stderr "TIMEOUT waiting for u-boot>"
        exit 1
    }
}
EXPECT
    )
}

# Actually, expect with raw serial is tricky after catch-uboot.py closed it.
# Let's use a single expect session for all commands instead.

echo "Starting flash procedure via expect..."

expect -f <(cat <<'EXPECT_SCRIPT'
set timeout 30
log_user 1

spawn -noecho sudo picocom -b 9600 --noreset /dev/ttyUSB0
expect "Terminal ready"
sleep 1

# Verify we're at u-boot prompt
send "\r"
expect {
    "u-boot>" { }
    timeout {
        puts stderr "ERROR: Not at U-Boot prompt"
        exit 1
    }
}

puts "\n>>> Step 1: Erase U-Boot env (mtd7)"
send "nand erase 0xe600000 0x100000\r"
expect {
    "u-boot>" { }
    timeout { puts stderr "TIMEOUT on mtd7 erase"; exit 1 }
}

puts "\n>>> Step 2: Flash kernel (mtd4) — ~14 MB"
set timeout 120
send "tftpboot 0x10000000 mtd4_kernel.bin\r"
expect {
    "u-boot>" { }
    timeout { puts stderr "TIMEOUT on mtd4 tftp"; exit 1 }
}
send "nand erase 0xe00000 0xe00000\r"
expect {
    "u-boot>" { }
    timeout { puts stderr "TIMEOUT on mtd4 erase"; exit 1 }
}
send "nand write 0x10000000 0xe00000 ${filesize}\r"
expect {
    -re {nand write.*\n.*u-boot>} { }
    "u-boot>" { }
    timeout { puts stderr "TIMEOUT on mtd4 write"; exit 1 }
}

puts "\n>>> Step 3: Flash DTS (mtd5) — ~2 MB"
set timeout 60
send "tftpboot 0x10000000 mtd5_dts.bin\r"
expect {
    "u-boot>" { }
    timeout { puts stderr "TIMEOUT on mtd5 tftp"; exit 1 }
}
send "nand erase 0x1c00000 0x200000\r"
expect {
    "u-boot>" { }
    timeout { puts stderr "TIMEOUT on mtd5 erase"; exit 1 }
}
send "nand write 0x10000000 0x1c00000 ${filesize}\r"
expect {
    -re {nand write.*\n.*u-boot>} { }
    "u-boot>" { }
    timeout { puts stderr "TIMEOUT on mtd5 write"; exit 1 }
}

puts "\n>>> Step 4: Flash rootfs (mtd6) — ~200 MB (this takes a while)"
set timeout 600
send "tftpboot 0x10000000 mtd6_appimage.bin\r"
expect {
    "u-boot>" { }
    timeout { puts stderr "TIMEOUT on mtd6 tftp"; exit 1 }
}
set timeout 300
send "nand erase 0x1e00000 0xc800000\r"
expect {
    "u-boot>" { }
    timeout { puts stderr "TIMEOUT on mtd6 erase"; exit 1 }
}
send "nand write 0x10000000 0x1e00000 ${filesize}\r"
expect {
    "u-boot>" { }
    timeout { puts stderr "TIMEOUT on mtd6 write"; exit 1 }
}

puts "\n>>> Step 5: Booting stock firmware..."
send "reset\r"
sleep 2

# Exit picocom
send "\x01\x18"
expect eof

puts "\n>>> RESTORE COMPLETE — AP630 rebooting into HiveOS"
EXPECT_SCRIPT
) 2>&1

echo ""
echo "Restore complete. AP630 should boot into HiveOS."
echo "Default login: admin / aerohive"
echo "Verify with: show version (should show IQ Engine 10.6r7)"
