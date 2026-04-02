#!/bin/bash
# TFTP boot test for AP630 — the inner loop of kernel iteration.
#
# Reboots the AP (or catches it at U-Boot), loads kernel+DTB+initramfs via
# TFTP, boots, and captures filtered kernel output.
#
# Usage:
#   tftp-boot-test.sh                        # Boot with defaults from /srv/tftp/
#   tftp-boot-test.sh -k my-kernel.uboot     # Override kernel image
#   tftp-boot-test.sh -t 120                 # Wait 120s for boot (default 90)
#   tftp-boot-test.sh --no-reboot            # Assume already at U-Boot prompt
#   tftp-boot-test.sh --log boot.log         # Also save raw output to file
#
# Output: Filtered boot log showing only useful lines. Exit codes:
#   0 = reached initramfs shell ("TEST BOOT SUCCESSFUL")
#   1 = kernel panic or hang (timeout)
#   2 = U-Boot error (TFTP fail, decompress fail, etc.)
#   3 = serial/connectivity error

set -euo pipefail

SERIAL_DEV="/dev/ttyUSB0"
BAUD=9600
UBOOT_PW='AhNf?d@ta06'
HIVEOS_USER="admin"
HIVEOS_PW="aerohive"
AP_IP="192.168.1.201"
SERVER_IP="192.168.1.100"
KERNEL="kernel-6.12-ap630.uboot"
DTB="bcm4906-aerohive-ap630.dtb"
INITRAMFS="test-initramfs.uboot"
BOOT_TIMEOUT=90
DO_REBOOT=1
RAW_LOG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -k|--kernel)    KERNEL="$2"; shift 2 ;;
        -d|--dtb)       DTB="$2"; shift 2 ;;
        -i|--initramfs) INITRAMFS="$2"; shift 2 ;;
        -t|--timeout)   BOOT_TIMEOUT="$2"; shift 2 ;;
        --no-reboot)    DO_REBOOT=0; shift ;;
        --log)          RAW_LOG="$2"; shift 2 ;;
        -h|--help)      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *)              echo "Unknown arg: $1" >&2; exit 3 ;;
    esac
done

for f in "$KERNEL" "$DTB" "$INITRAMFS"; do
    if [[ ! -f "/srv/tftp/$f" ]]; then
        echo "MISSING: /srv/tftp/$f" >&2
        exit 3
    fi
done

KERNEL_SIZE=$(stat -c%s "/srv/tftp/$KERNEL" | numfmt --to=iec)
echo "=== AP630 TFTP Boot Test ==="
echo "  Kernel:    $KERNEL ($KERNEL_SIZE)"
echo "  DTB:       $DTB"
echo "  Initramfs: $INITRAMFS"
echo "  Timeout:   ${BOOT_TIMEOUT}s"
echo ""

cleanup() {
    sudo fuser -k "$SERIAL_DEV" 2>/dev/null || true
}
trap cleanup EXIT
sudo fuser -k "$SERIAL_DEV" 2>/dev/null || true
sleep 1

RAW_OUTFILE=$(mktemp /tmp/ap630-boot-XXXXXX.log)

# Generate the expect script as a temp file so it's one coherent unit
EXPECT_SCRIPT=$(mktemp /tmp/ap630-expect-XXXXXX.exp)
trap "rm -f '$EXPECT_SCRIPT' '$RAW_OUTFILE'; cleanup" EXIT

cat > "$EXPECT_SCRIPT" <<'EXPECTEOF'
# --- Params injected by shell (replaced below) ---
set serial_dev  "@@SERIAL_DEV@@"
set baud        "@@BAUD@@"
set uboot_pw    "@@UBOOT_PW@@"
set ap_ip       "@@AP_IP@@"
set server_ip   "@@SERVER_IP@@"
set kernel      "@@KERNEL@@"
set dtb         "@@DTB@@"
set initramfs   "@@INITRAMFS@@"
set boot_timeout @@BOOT_TIMEOUT@@
set do_reboot   @@DO_REBOOT@@
set raw_log     "@@RAW_OUTFILE@@"
set uboot_user  "@@UBOOT_USER@@"
set uboot_hiveos_pw "@@UBOOT_HIVEOS_PW@@"

log_user 0
set timeout 30

set raw_fd [open $raw_log w]

# --- Filtered output ---
proc emit {line} {
    global raw_fd
    puts $raw_fd $line
    flush $raw_fd

    set t [string trim $line]
    if {$t eq ""} return
    # Skip TFTP transfer dots
    if {[regexp {^[.#]+$} $t]} return
    if {[regexp {^\s*[.#]{10,}} $t]} return
    # Skip picocom/spawn noise
    if {[string match "*picocom*" $t]} return
    if {[string match "Terminal ready*" $t]} return
    # Skip bare U-Boot prompt echo
    if {[regexp {^u-boot>\s*$} $t]} return
    # Skip NAND erase progress
    if {[string match "*Erasing*complete*" $t]} return

    # Highlight milestones
    if {[string match "*Starting kernel*" $t]} {
        puts stdout ""
        puts stdout ">>> KERNEL START <<<"
    }
    if {[string match "*TEST BOOT SUCCESSFUL*" $t]} {
        puts stdout ""
        puts stdout ">>> BOOT SUCCESSFUL <<<"
    }
    if {[string match "*Kernel panic*" $t]} {
        puts stdout ""
        puts stdout ">>> KERNEL PANIC <<<"
    }
    if {[string match "*Firmware Bug*" $t]} {
        puts stdout ">>> FW BUG: $t <<<"
    }

    puts stdout $t
    flush stdout
}

# Custom log: capture all output and filter it
proc eat_output {} {
    global spawn_id
    expect {
        -re {([^\r\n]+)\r?\n} {
            emit $expect_out(1,string)
            exp_continue
        }
        timeout {}
        eof {}
    }
}

# --- Connect ---
spawn -noecho sudo picocom -b $baud --noreset $serial_dev
expect "Terminal ready"
sleep 1

# --- Get to U-Boot prompt ---
if {$do_reboot} {
    # Reboot strategy:
    # 1. Probe current state
    # 2. If responsive (login/CLI/root shell): CLI reboot → catch U-Boot
    # 3. If unresponsive (hung kernel): PoE cycle → wait for HiveOS → CLI reboot → catch U-Boot
    send "\r"
    sleep 2
    send "\r"
    sleep 3

    set need_poe 0
    expect {
        "u-boot>" {
            puts stdout ">>> Already at U-Boot, resetting <<<"
            send "reset\r"
        }
        -re {login:\s*$} {
            puts stdout ">>> At login, logging in to reboot <<<"
            send "$uboot_user\r"
            expect -re {assword:}
            send "$uboot_hiveos_pw\r"
            sleep 3
            expect -re {AH-[0-9a-f]+#}
            send "reboot\r"
            sleep 2
            expect { -re {Y/N|y/n} { send "Y\r" } timeout {} }
        }
        -re {AH-[0-9a-f]+#} {
            puts stdout ">>> At CLI, rebooting <<<"
            send "reboot\r"
            sleep 2
            expect { -re {Y/N|y/n} { send "Y\r" } timeout {} }
        }
        -re {/tmp/home/admin} {
            puts stdout ">>> At root shell, rebooting <<<"
            send "reboot\r"
        }
        -re {Do you really want to reboot} {
            send "Y\r"
        }
        timeout {
            puts stdout ">>> No response — PoE cycling <<<"
            set need_poe 1
        }
    }

    if {$need_poe} {
        system "bash @@SCRIPT_DIR@@/power-cycle-ap.sh 5"
        puts stdout ">>> Waiting for HiveOS after PoE cycle <<<"
        set timeout 180
        expect {
            -re {login:\s*$} {
                puts stdout ">>> HiveOS up, rebooting <<<"
                send "$uboot_user\r"
                expect -re {assword:}
                send "$uboot_hiveos_pw\r"
                sleep 3
                expect -re {AH-[0-9a-f]+#}
                send "reboot\r"
                sleep 2
                expect { -re {Y/N|y/n} { send "Y\r" } timeout {} }
            }
            timeout {
                puts stdout ">>> TIMEOUT waiting for HiveOS after PoE cycle <<<"
                exit 3
            }
        }
    }

    # Catch U-Boot autoboot
    puts stdout ">>> Catching U-Boot <<<"
    set timeout 120
    expect {
        "Hit any key" {
            send " "
            puts stdout ">>> Got autoboot prompt <<<"
        }
        timeout {
            puts stdout ">>> TIMEOUT waiting for U-Boot <<<"
            exit 3
        }
    }

    set timeout 10
    expect {
        "assword:" { send "$uboot_pw\r" }
        "u-boot>" { }
        timeout { puts stdout ">>> TIMEOUT after interrupt <<<"; exit 3 }
    }
    expect { -timeout 5 "u-boot>" {} timeout {} }

    # Verify
    send "version\r"
    set timeout 5
    expect {
        "Boot Loader" { puts stdout ">>> U-Boot verified <<<" }
        timeout { puts stdout ">>> NOT at U-Boot <<<"; exit 3 }
    }
    expect { -timeout 2 "u-boot>" {} timeout {} }
} else {
    send "\r"
    expect {
        timeout {
            puts stdout ">>> Not at U-Boot prompt <<<"
            exit 3
        }
        "u-boot>" {}
    }
    puts stdout ">>> U-Boot prompt ready (no reboot) <<<"
}

# --- TFTP load sequence ---
puts stdout ">>> Loading kernel: $kernel <<<"
send "setenv ipaddr $ap_ip\r"
expect "u-boot>"
send "setenv serverip $server_ip\r"
expect "u-boot>"

send "tftpboot 0x01005000 $kernel\r"
set timeout 30
expect {
    timeout { puts stdout ">>> TFTP timeout loading kernel <<<"; exit 2 }
    "TFTP error*" { puts stdout ">>> TFTP error loading kernel <<<"; exit 2 }
    "Bytes transferred" {}
}
expect "u-boot>"
puts stdout ">>> Kernel loaded <<<"

puts stdout ">>> Loading DTB: $dtb <<<"
send "tftpboot 0x05005000 $dtb\r"
expect {
    timeout { puts stdout ">>> TFTP timeout loading DTB <<<"; exit 2 }
    "TFTP error*" { puts stdout ">>> TFTP error loading DTB <<<"; exit 2 }
    "Bytes transferred" {}
}
expect "u-boot>"

puts stdout ">>> Loading initramfs: $initramfs <<<"
send "tftpboot 0x02005000 $initramfs\r"
expect {
    timeout { puts stdout ">>> TFTP timeout loading initramfs <<<"; exit 2 }
    "TFTP error*" { puts stdout ">>> TFTP error loading initramfs <<<"; exit 2 }
    "Bytes transferred" {}
}
expect "u-boot>"
puts stdout ">>> All files loaded, booting <<<"

# --- Set bootargs and boot ---
send "setenv bootargs coherent_pool=4M cpuidle_sysfs_switch pci=pcie_bus_safe root=/dev/ram console=ttyS0,9600 ramdisk_size=70000 cache-sram-size=0x10000\r"
expect "u-boot>"

send "bootm 0x01005000 0x02005000 0x05005000\r"

# --- Capture boot output ---
set timeout $boot_timeout
expect {
    -re {([^\r\n]*)\r?\n} {
        set line $expect_out(1,string)
        emit $line

        if {[string match "*TEST BOOT SUCCESSFUL*" $line]} {
            # Success! Let a few more lines print
            sleep 3
            close $raw_fd
            send "\x01\x18"
            expect eof
            exit 0
        }
        if {[string match "*end Kernel panic*" $line]} {
            sleep 2
            close $raw_fd
            send "\x01\x18"
            expect eof
            exit 1
        }
        if {[string match "*Must RESET*" $line]} {
            close $raw_fd
            send "\x01\x18"
            expect eof
            exit 2
        }
        exp_continue
    }
    timeout {
        puts stdout ""
        puts stdout ">>> BOOT TIMEOUT (${boot_timeout}s) — kernel hung <<<"
        close $raw_fd
        send "\x01\x18"
        expect eof
        exit 1
    }
    eof {
        close $raw_fd
        exit 3
    }
}
EXPECTEOF

# Inject shell variables into the expect script
sed -i \
    -e "s|@@SERIAL_DEV@@|$SERIAL_DEV|g" \
    -e "s|@@BAUD@@|$BAUD|g" \
    -e "s|@@UBOOT_PW@@|$UBOOT_PW|g" \
    -e "s|@@AP_IP@@|$AP_IP|g" \
    -e "s|@@SERVER_IP@@|$SERVER_IP|g" \
    -e "s|@@KERNEL@@|$KERNEL|g" \
    -e "s|@@DTB@@|$DTB|g" \
    -e "s|@@INITRAMFS@@|$INITRAMFS|g" \
    -e "s|@@BOOT_TIMEOUT@@|$BOOT_TIMEOUT|g" \
    -e "s|@@DO_REBOOT@@|$DO_REBOOT|g" \
    -e "s|@@RAW_OUTFILE@@|$RAW_OUTFILE|g" \
    -e "s|@@UBOOT_USER@@|$HIVEOS_USER|g" \
    -e "s|@@UBOOT_HIVEOS_PW@@|$HIVEOS_PW|g" \
    -e "s|@@SCRIPT_DIR@@|$(cd "$(dirname "$0")" && pwd)|g" \
    "$EXPECT_SCRIPT"

# Run it
set +e
expect -f "$EXPECT_SCRIPT" 2>&1 | sed 's/\r//g'
EXIT_CODE=${PIPESTATUS[0]}
set -e

# Save raw log if requested
if [[ -n "$RAW_LOG" ]] && [[ -f "$RAW_OUTFILE" ]]; then
    cp "$RAW_OUTFILE" "$RAW_LOG"
    echo "Raw log: $RAW_LOG"
fi

echo ""
case $EXIT_CODE in
    0) echo "=== RESULT: SUCCESS ===" ;;
    1) echo "=== RESULT: FAIL — kernel panic or hang ===" ;;
    2) echo "=== RESULT: FAIL — U-Boot error ===" ;;
    3) echo "=== RESULT: FAIL — serial/connectivity ===" ;;
esac
exit $EXIT_CODE
