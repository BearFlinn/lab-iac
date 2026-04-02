#!/bin/bash
# AP630 serial console helper
# Handles the expect-based interaction with the AP630 and cleans up output
#
# Usage:
#   ap630-serial.sh run "command1" "command2" ...  — run commands in root shell
#   ap630-serial.sh uboot "command1" "command2" ... — run commands in U-Boot (requires reboot!)
#   ap630-serial.sh watch-boot                      — reboot and capture clean boot log

set -euo pipefail

SERIAL_DEV="/dev/ttyUSB0"
BAUD=9600
UBOOT_PW="AhNf?d@ta06"
HIVEOS_USER="admin"
HIVEOS_PW="aerohive"

# Clean up character-doubled output from expect/picocom
# The doubling happens because serial echo + expect capture overlap
dedupe_output() {
    # Remove picocom header, then de-duplicate doubled lines
    sed '/^picocom/,/^Terminal ready$/d' | \
    sed 's/\r//g' | \
    grep -v '^$' | \
    cat
}

cleanup() {
    sudo fuser -k "$SERIAL_DEV" 2>/dev/null || true
}
trap cleanup EXIT

run_in_root_shell() {
    local commands=("$@")

    sudo fuser -k "$SERIAL_DEV" 2>/dev/null || true
    sleep 2

    local expect_cmds=""
    for cmd in "${commands[@]}"; do
        expect_cmds+="
send \"$cmd\r\"
sleep 3
expect -re {/tmp/home/admin #}
puts \$expect_out(buffer)
"
    done

    expect -f <(cat <<EXPECT_SCRIPT
set timeout 30
log_user 0

spawn -noecho sudo picocom -b $BAUD --noreset $SERIAL_DEV
expect "Terminal ready"
sleep 1
send "\r"
sleep 3

expect {
    -re {/tmp/home/admin #} { }
    -re {AH-[0-9a-f]+#} {
        send "ssh-tunnel server 0 tunnel-port 8080 user $HIVEOS_USER password \"a sh -c sh\"\r"
        sleep 5
        send "exit\r"
        sleep 3
        expect -re {/tmp/home/admin #}
    }
    -re {login:} {
        send "$HIVEOS_USER\r"
        sleep 1
        expect -re {assword:}
        send "$HIVEOS_PW\r"
        sleep 3
        expect -re {AH-[0-9a-f]+#}
        send "ssh-tunnel server 0 tunnel-port 8080 user $HIVEOS_USER password \"a sh -c sh\"\r"
        sleep 5
        send "exit\r"
        sleep 3
        expect -re {/tmp/home/admin #}
    }
}

log_user 1
$expect_cmds

send "\x01\x18"
expect eof
EXPECT_SCRIPT
    ) 2>&1 | dedupe_output
}

echo_usage() {
    echo "Usage: $0 {run|uboot|watch-boot} [commands...]"
    echo "  run cmd1 cmd2 ...  — run commands in root shell"
    echo "  uboot cmd1 ...     — run commands at U-Boot prompt (reboots!)"
    echo "  watch-boot         — reboot and capture boot log"
}

case "${1:-}" in
    run)
        shift
        run_in_root_shell "$@"
        ;;
    *)
        echo_usage
        exit 1
        ;;
esac
