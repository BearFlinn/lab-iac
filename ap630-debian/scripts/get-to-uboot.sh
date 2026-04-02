#!/bin/bash
# Get the AP630 to the U-Boot prompt reliably.
# Handles any starting state: hung, login, CLI, root shell, U-Boot.
#
# Usage: get-to-uboot.sh
# Exit 0 = at U-Boot prompt (serial is released for next tool)
# Exit 1 = failed

set -euo pipefail

SERIAL_DEV="/dev/ttyUSB0"
BAUD=9600
UBOOT_PW='AhNf?d@ta06'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

sudo fuser -k "$SERIAL_DEV" 2>/dev/null || true
sleep 1

MAX_ATTEMPTS=3
for attempt in $(seq 1 $MAX_ATTEMPTS); do
    echo "Attempt $attempt/$MAX_ATTEMPTS"

    RESULT=$(expect -c "
    log_user 0
    set timeout 10
    spawn -noecho sudo picocom -b $BAUD --noreset $SERIAL_DEV
    expect \"Terminal ready\"
    sleep 1

    # Probe: send newlines and see what we get
    send \"\r\"
    sleep 3
    send \"\r\"
    sleep 3

    expect {
        \"u-boot>\" { puts \"AT_UBOOT\" }
        -re {login:\\s*\$} { puts \"AT_LOGIN\" }
        -re {AH-\[0-9a-f\]+#} { puts \"AT_CLI\" }
        -re {/tmp/home/admin} { puts \"AT_ROOT\" }
        -re {Y/N} { puts \"AT_REBOOT_CONFIRM\" }
        timeout { puts \"NO_RESPONSE\" }
    }

    send \"\x01\x18\"
    expect eof
    " 2>&1 | grep -E 'AT_|NO_RESPONSE' | head -1)

    echo "  State: $RESULT"

    case "$RESULT" in
        AT_UBOOT)
            echo "Already at U-Boot"
            exit 0
            ;;
        AT_REBOOT_CONFIRM)
            # Send Y and wait for U-Boot
            expect -c "
            log_user 0
            set timeout 120
            spawn -noecho sudo picocom -b $BAUD --noreset $SERIAL_DEV
            expect \"Terminal ready\"
            send \"Y\r\"
            expect {
                \"Hit any key\" { send \" \"; puts \"AUTOBOOT\" }
                timeout { puts \"TIMEOUT\" }
            }
            if {\[string match \"AUTOBOOT\" *\]} {
                expect \"assword:\"
                send \"$UBOOT_PW\r\"
                expect \"u-boot>\"
                puts \"AT_UBOOT\"
            }
            send \"\x01\x18\"
            expect eof
            " 2>&1 | grep -q 'AT_UBOOT' && exit 0
            ;;
        AT_LOGIN|AT_CLI|AT_ROOT)
            # Login if needed, then reboot
            expect -c "
            log_user 0
            set timeout 30
            spawn -noecho sudo picocom -b $BAUD --noreset $SERIAL_DEV
            expect \"Terminal ready\"
            sleep 1

            if {\"$RESULT\" eq \"AT_LOGIN\"} {
                send \"admin\r\"
                sleep 1
                expect -re {assword:}
                send \"aerohive\r\"
                sleep 5
                expect -re {AH-\[0-9a-f\]+#}
            } elseif {\"$RESULT\" eq \"AT_ROOT\"} {
                send \"reboot\r\"
                sleep 120
                # After reboot from root shell, should go straight to U-Boot
                expect {
                    \"Hit any key\" { send \" \"; puts \"AUTOBOOT\" }
                    timeout { puts \"TIMEOUT\" }
                }
                send \"\x01\x18\"
                expect eof
                exit
            } else {
                send \"\r\"
                sleep 1
                expect -re {AH-\[0-9a-f\]+#}
            }

            send \"reboot\r\"
            set timeout 30
            expect {
                -re {Y/N} { send \"Y\r\" }
                timeout { }
            }

            set timeout 120
            expect {
                \"Hit any key\" {
                    send \" \"
                    expect \"assword:\"
                    send \"$UBOOT_PW\r\"
                    expect \"u-boot>\"
                    puts \"AT_UBOOT\"
                }
                timeout { puts \"TIMEOUT_AUTOBOOT\" }
            }

            send \"\x01\x18\"
            expect eof
            " 2>&1 | grep -q 'AT_UBOOT' && exit 0
            echo "  Reboot didn't reach U-Boot"
            ;;
        NO_RESPONSE)
            echo "  No response — PoE cycling"
            bash "$SCRIPT_DIR/power-cycle-ap.sh" 5
            echo "  Waiting 120s for HiveOS boot..."
            sleep 120
            ;;
    esac

    sudo fuser -k "$SERIAL_DEV" 2>/dev/null || true
    sleep 2
done

echo "Failed after $MAX_ATTEMPTS attempts"
exit 1
