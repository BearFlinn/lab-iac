#!/usr/bin/env python3
"""Catch the AP630 at the U-Boot prompt.

Sends space characters every 100ms on the serial port while waiting for
the U-Boot autoboot interrupt window. Much more reliable than expect
because it doesn't wait to process buffered output before sending.

Usage:
    catch-uboot.py                  # Assumes AP is rebooting
    catch-uboot.py --poe            # PoE cycle first
    catch-uboot.py --reboot         # Send reboot -f first

Exit code 0 = at U-Boot prompt, serial port left open on stdout.
"""

import sys, time, os, subprocess, threading, argparse, select

SERIAL_DEV = "/dev/ttyUSB0"
BAUD = 9600
UBOOT_PW = "AhNf?d@ta06"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

try:
    import serial
except ImportError:
    sys.exit("pip install pyserial")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--poe", action="store_true")
    parser.add_argument("--reboot", action="store_true")
    args = parser.parse_args()

    ser = serial.Serial(SERIAL_DEV, BAUD, timeout=0.1)
    ser.reset_input_buffer()

    buf = b""

    def read_and_print():
        """Read serial data, accumulate in buf, print to stderr."""
        nonlocal buf
        data = ser.read(4096)
        if data:
            buf += data
            sys.stderr.buffer.write(data)
            sys.stderr.buffer.flush()
        return data

    if args.reboot:
        print(">>> Sending reboot -f", file=sys.stderr)
        ser.write(b"\r")
        time.sleep(1)
        ser.write(b"reboot -f\r")
        time.sleep(2)
    elif args.poe:
        print(">>> PoE cycling", file=sys.stderr)
        subprocess.Popen(
            ["bash", f"{SCRIPT_DIR}/power-cycle-ap.sh", "3"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

    # Phase 1: Spam spaces to catch autoboot (60 seconds)
    print(">>> Spamming space to catch autoboot...", file=sys.stderr)
    deadline = time.time() + 60
    caught = False
    while time.time() < deadline:
        ser.write(b" ")
        time.sleep(0.1)
        read_and_print()

        if b"assword:" in buf[-200:]:
            # Stop spamming! Drain any buffered spaces from the serial line,
            # then send the real password on a clean line.
            print("\n>>> Password prompt!", file=sys.stderr)
            time.sleep(1)
            ser.reset_input_buffer()
            # Send CR to clear any spaces in the password field, then password
            ser.write(b"\r")
            time.sleep(0.5)
            read_and_print()
            ser.write(f"{UBOOT_PW}\r".encode())
            time.sleep(2)
            read_and_print()
            # If wrong password re-prompted, try once more on clean line
            if b"assword:" in buf[-200:]:
                print(">>> Retrying password...", file=sys.stderr)
                time.sleep(0.3)
                ser.write(f"{UBOOT_PW}\r".encode())
                time.sleep(2)
                read_and_print()
            caught = True
            break
        if b"u-boot>" in buf[-100:]:
            print("\n>>> At U-Boot!", file=sys.stderr)
            caught = True
            break
        if b"Hit any key" in buf[-200:]:
            # Already sending spaces, just keep going
            pass

    if not caught:
        print(">>> TIMEOUT — didn't catch U-Boot", file=sys.stderr)
        ser.close()
        sys.exit(3)

    # Phase 2: Wait for u-boot> prompt
    deadline2 = time.time() + 10
    while time.time() < deadline2:
        read_and_print()
        if b"u-boot>" in buf[-100:]:
            break
        time.sleep(0.1)

    if b"u-boot>" not in buf[-100:]:
        print(">>> No u-boot> prompt", file=sys.stderr)
        ser.close()
        sys.exit(3)

    print("\n>>> AT U-BOOT PROMPT <<<", file=sys.stderr)
    ser.close()
    sys.exit(0)

if __name__ == "__main__":
    main()
