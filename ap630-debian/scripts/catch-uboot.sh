#!/bin/bash
# Catch the AP630 at its U-Boot prompt.
#
# Reboots from whatever state the AP is in (Debian, BusyBox, HiveOS, hung)
# and catches the U-Boot autoboot prompt. Leaves picocom connected at the
# U-Boot prompt for manual commands, or exits with $? == 0 for scripting.
#
# Usage:
#   catch-uboot.sh              # Reboot + catch, stay connected
#   catch-uboot.sh --script     # Reboot + catch, exit cleanly (for pipelines)
#   catch-uboot.sh --poe        # Force PoE cycle instead of software reboot
#
# Exit codes:
#   0 = at U-Boot prompt
#   3 = failed to reach U-Boot

set -euo pipefail

SERIAL_DEV="/dev/ttyUSB0"
BAUD=9600
UBOOT_PW='AhNf?d@ta06'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="interactive"
USE_POE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --script) MODE="script"; shift ;;
        --poe)    USE_POE=1; shift ;;
        -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "Unknown: $1" >&2; exit 1 ;;
    esac
done

sudo fuser -k "$SERIAL_DEV" 2>/dev/null || true
sleep 1

EXPECT_SCRIPT=$(mktemp /tmp/catch-uboot-XXXXXX.exp)
trap "rm -f '$EXPECT_SCRIPT'" EXIT

cat > "$EXPECT_SCRIPT" <<EXPEOF
set timeout 10
log_user 1

spawn -noecho sudo picocom -b $BAUD --noreset $SERIAL_DEV
expect "Terminal ready"
sleep 1

# Probe current state
send "\r"
sleep 3

set at_uboot 0
expect {
    "u-boot>" {
        set at_uboot 1
    }
    -re {login:\s*$} {
        puts "\n>>> At login, rebooting <<<"
        send "root\r"
        sleep 2
        expect { "assword:" { send "root\r"; sleep 2 } -re {#|\$} { } timeout { } }
        expect -re {#|\$}
        send "reboot\r"
    }
    -re {#|\$} {
        puts "\n>>> At shell, sysrq rebooting <<<"
        send "echo b > /proc/sysrq-trigger\r"
    }
    -re {AH-[0-9a-f]+#} {
        puts "\n>>> At HiveOS CLI, rebooting <<<"
        send "reboot\r"
        sleep 2
        expect { -re {Y/N|y/n} { send "Y\r" } timeout {} }
    }
    timeout {
        if {$USE_POE} {
            puts "\n>>> No response, PoE cycling <<<"
            system "bash $SCRIPT_DIR/power-cycle-ap.sh 5"
        } else {
            puts "\n>>> No response, trying sysrq <<<"
            send "echo b > /proc/sysrq-trigger\r"
            sleep 3
            send "\r"
            sleep 2
            expect {
                -re {#|\$|login:} { }
                timeout {
                    puts "\n>>> Still dead, PoE cycling <<<"
                    system "bash $SCRIPT_DIR/power-cycle-ap.sh 5"
                }
            }
        }
    }
}

if {!\$at_uboot} {
    puts "\n>>> Waiting for U-Boot autoboot (up to 3 min) <<<"
    set timeout 180
    expect {
        "Hit any key" {
            send " "
            puts "\n>>> Caught autoboot <<<"
        }
        timeout {
            puts "\n>>> TIMEOUT — U-Boot not reached <<<"
            send "\x01\x18"
            expect eof
            exit 3
        }
    }

    set timeout 10
    expect {
        "assword:" { send "$UBOOT_PW\r" }
        "u-boot>" { }
        timeout { }
    }
    expect "u-boot>"
}

puts "\n>>> At U-Boot prompt <<<"

if {"$MODE" eq "script"} {
    send "\x01\x18"
    expect eof
    exit 0
} else {
    puts ">>> Interactive mode — Ctrl-A Ctrl-X to exit <<<"
    interact
}
EXPEOF

sed -i "s|\$USE_POE|$USE_POE|g; s|\$MODE|$MODE|g; s|\$SCRIPT_DIR|$SCRIPT_DIR|g" "$EXPECT_SCRIPT"

expect -f "$EXPECT_SCRIPT" 2>&1
