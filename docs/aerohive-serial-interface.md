# Aerohive Device Management Interface

How to interact with Aerohive HiveOS devices (SR2024 switch, AP130/AP230 APs) from the MSI laptop. Covers serial console, SSH, and web UI access, plus implementation details for scripting and a potential MCP server.

## Management Interfaces

| Interface | SR2024 Switch | AP230 | AP130 |
|-----------|:---:|:---:|:---:|
| Serial console | Yes | Yes | Yes |
| SSH | Yes (OpenSSH 5.9) | Yes (OpenSSH 7.2) | Yes (OpenSSH 5.9) |
| Web UI | Read-only (limited) | Yes (full) | Yes (full) |

**Web UI details:**
- APs serve a PHP-based management UI at `https://<ip>/` (redirects to `/index.php5`). Same `admin`/`aerohive` credentials. Allows configuration changes.
- The SR2024 switch has a web server that responds on HTTP and HTTPS, but returns **503 Service Unavailable** on factory default config. Per the previous owner, the web interface works but doesn't let you change anything meaningful — CLI/SSH is the real management path for the switch.

**SSH** is the most practical option for day-to-day management — same CLI as console, no cable swapping, works on all four devices. Serial console is needed for initial setup, recovery, and when the network isn't configured yet.

## Serial Console Setup

| Detail | Value |
|--------|-------|
| Serial device | `/dev/ttyUSB0` (USB console cable) |
| Baud rate | 9600 |
| Data bits | 8 |
| Parity | None |
| Stop bits | 1 |
| Flow control | None |
| OS group | `dialout` (user `bearf` has been added) |

### Connection Tools

**picocom** is installed. For interactive use from a TTY:
```bash
picocom -b 9600 --noreset /dev/ttyUSB0
# Exit: Ctrl-A, Ctrl-X
```

**expect** is installed and is the right tool for scripted/automated interaction (picocom alone can't drive commands from a non-TTY context like Claude Code or scripts).

**nmap** and **dnsmasq** are installed for network discovery and temporary DHCP.

## Network Access

All devices have DHCP enabled on their management interface (mgt0) and will request an address on VLAN 1. When connected to the switch with no DHCP server available, run a temporary dnsmasq instance on the USB ethernet adapter:

```bash
# USB ethernet adapter: enx00e04c2c62c0
sudo ip addr add 192.168.1.100/16 dev enx00e04c2c62c0

sudo dnsmasq --no-daemon \
  --interface=enx00e04c2c62c0 \
  --bind-interfaces \
  --dhcp-range=192.168.1.200,192.168.1.250,255.255.255.0,1h \
  --log-dhcp \
  --no-resolv \
  --no-hosts
```

The switch also gets a DHCP address (default subnet 192.168.0.0/16). All devices identify themselves via DHCP with vendor class `AEROHIVE` and hostname `AH-XXXXXX`.

Note: the switch management interface defaults to a /16 subnet (255.255.0.0), so ensure the laptop adapter uses a matching or broader mask.

## Authentication

| Field | Factory Default |
|-------|----------------|
| Username | `admin` |
| Password | `aerohive` |

Login prompt format (serial/SSH):
```
Welcome to Aerohive Product

AH-XXXXXX login:
```

The hostname `AH-XXXXXX` is derived from the last 6 hex chars of the management MAC. After successful login, the prompt is `AH-XXXXXX#` (privileged mode, no enable step needed).

## CLI Behavior

### Prompt
- Command prompt: `AH-XXXXXX#`
- No `enable` or privilege escalation — you're in exec mode immediately after login
- Confirmation prompts use `(Y/N)` format

### Paging
- Long output triggers `--More--` paging
- Send a space character to advance one page
- There is no `terminal length 0` equivalent discovered yet — scripts must handle `--More--`

### Command Echo
- Commands are echoed back on the serial line
- When parsing output, skip the first line (the echoed command) and read until the next `#` prompt

### Save Behavior
- Config changes are **not persistent** until `save config` is run
- `reset config` prompts `(Y/N)` then **reboots the device**
- Boot time is approximately 45–60 seconds for the switch, ~60 seconds for APs
- **Factory reset re-enables CAPWAP.** After any reset, the first commands must be `no capwap client enable` + `save config` to prevent the device from trying to phone home to Extreme's cloud.

### Error Format
- `ERROR: Incomplete command` — command exists but needs more arguments (e.g., `show vlan` is incomplete, needs a subcommand)
- `^-- unknown keyword or invalid input` — command or keyword doesn't exist
- `^-- Ambiguous input` — multiple commands match the prefix
- Referencing non-existent objects silently succeeds in some cases (e.g., binding a misspelled security object) — verify config after applying

## Boot Sequences

### SR2024 Switch
1. Bootloader message with `Hit the space bar to stop the autoboot process: 3 2 1`
2. Kernel and driver init (takes ~30–40 seconds)
3. `System ready.` message
4. Login prompt: `Welcome to Aerohive Product\n\nAH-XXXXXX login:`

### APs (AP230/AP130)
Similar but longer (~60 seconds) and more verbose:
1. U-Boot bootloader with `Hit any key to stop autoboot: 3 2 1 0`
2. Linux kernel load and decompress from NAND
3. `POE Input Detection -> AT` — confirms PoE power source
4. Broadcom radio init (`BCM radio init config` ... `BCM radio init config done`)
5. `System ready.` or direct to login prompt
6. `Welcome to Aerohive Product\n\nAH-XXXXXX login:`

Key boot messages to watch for in expect scripts:
- `"Hit the space bar to stop"` or `"Hit any key to stop"` — bootloader, do NOT send space/key unless you want recovery
- `"System ready."` — OS is up, login prompt follows shortly
- `"login:"` — ready for credentials

## Scripting Patterns

### Device-specific quirks

The SR2024 switch and the APs behave differently over serial, even though they both run HiveOS:

**SR2024 switch:**
- Strict prompt matching with `expect "#"` often fails — the prompt arrives fragmented or with extra `\r\n` padding that breaks pattern matching.
- Sending commands too fast causes `ttyS0: input overrun(s)` errors — the switch drops characters.
- The broad-match approach (see "reliable template" below) with explicit `sleep` between commands works consistently. Precise `expect "#"` does not.
- Baud rate probe confirmed: 9600 is correct. 115200/38400/19200/57600 all returned nothing.

**APs (AP230 and AP130 both confirmed):**
- More forgiving — the original simple expect template with `expect "#"` works fine.
- No input overrun issues observed even with rapid command sequences.

**Port locking:** picocom holds an exclusive lock on `/dev/ttyUSB0`. If a previous session didn't exit cleanly, the next connection fails with `FATAL: cannot lock /dev/ttyUSB0: Resource temporarily unavailable`. Fix: `sudo fuser -k /dev/ttyUSB0` then wait 1–2 seconds before reconnecting.

### Basic expect script template (works for APs)

```expect
#!/usr/bin/expect -f
set timeout 15
set cmd [lindex $argv 0]

spawn -noecho sudo picocom -b 9600 --noreset /dev/ttyUSB0
expect "Terminal ready"

send "\r"
sleep 1

expect {
    "login:" {
        send "admin\r"
        expect "Password:"
        send "aerohive\r"
        expect "#"
    }
    "#" { }
}

send "$cmd\r"
expect {
    -re {--More--} {
        send " "
        exp_continue
    }
    "#" { }
}

# Exit picocom: Ctrl-A, Ctrl-X
send "\x01\x18"
expect eof
```

### Reliable template (works for switch AND APs)

Uses broad matching and sleeps to avoid overrun and prompt fragmentation issues:

```expect
#!/usr/bin/expect -f
set timeout 30

spawn -noecho sudo picocom -b 9600 --noreset /dev/ttyUSB0
expect "Terminal ready"
sleep 1

send "\r"
sleep 2

# Broad match — handles fragmented prompts
expect {
    -re {login:} {
        send "admin\r"
        sleep 1
        expect -re {.+}
        send "aerohive\r"
        sleep 2
        expect -re {.+}
    }
    -re {AH-} { }
    -re {#} { }
    timeout {
        puts "=== NO RESPONSE ==="
        send "\x01\x18"
        expect eof
        exit 1
    }
}

# Send commands with sleeps to avoid input overrun
send "some command\r"
sleep 2
expect -re {.+}

send "\x01\x18"
expect eof
```

### Handling confirmations (e.g., reset config)

```expect
send "reset config\r"
expect "(Y/N)"
send "Y\r"
# Device will reboot — wait for login prompt with long timeout
set timeout 120
expect "login:"
```

### Sending multiple commands sequentially

```expect
foreach cmd $command_list {
    send "$cmd\r"
    expect {
        -re {--More--} {
            send " "
            exp_continue
        }
        "#" { }
    }
}
```

### stty direct approach (simpler but less reliable)

Works for fire-and-forget commands but has no output synchronization:
```bash
sudo stty -F /dev/ttyUSB0 9600 cs8 -cstopb -parenb -echo raw
echo -e "command\r" | sudo tee /dev/ttyUSB0 > /dev/null
sudo timeout 5 cat /dev/ttyUSB0
```

Limitations: no prompt detection, no paging handling, output may be empty if timing is off. Prefer expect for anything beyond trivial use.

However, stty **is** useful for baud rate probing — cycle through common rates and see which one returns readable text:
```bash
for baud in 9600 115200 38400 19200 57600; do
  echo "=== Trying $baud ==="
  sudo stty -F /dev/ttyUSB0 "$baud" cs8 -cstopb -parenb -echo raw
  echo -e "\r\r" | sudo tee /dev/ttyUSB0 > /dev/null
  sudo timeout 3 cat /dev/ttyUSB0 2>/dev/null | cat -v
done
```

## MCP Server Design Notes

An MCP server for Aerohive device management should prefer **SSH over serial** for network-accessible devices, falling back to serial for initial setup or recovery. SSH avoids all the serial timing quirks and supports concurrent connections to multiple devices.

### Core Resources
- **Connection pool** — maintain SSH sessions to each device by IP/hostname. Fall back to serial when a device isn't network-accessible.
- **Serial port lock** — only one process can own `/dev/ttyUSB0` at a time. Use file locking to prevent conflicts when serial is needed.
- **Session state** — track whether each device is at login prompt, command prompt, or mid-boot. Reconnect/re-authenticate as needed.

### Suggested Tools
| Tool | Purpose |
|------|---------|
| `aerohive_run_command` | Send a single CLI command to a named device, return parsed output |
| `aerohive_run_commands` | Send a list of commands sequentially, return all output |
| `aerohive_show_run` | Convenience wrapper for `show run` with full paging |
| `aerohive_save_config` | Run `save config` |
| `aerohive_reset_config` | Factory reset with confirmation handling + wait for reboot (serial only) |
| `aerohive_get_status` | Connection state: device type, hostname, firmware, uptime |
| `aerohive_discover` | Run temporary DHCP server and report all devices that check in |

### Implementation Considerations
- **Transport:** Prefer `paramiko` (SSH) for network-connected devices. Use `pyserial` for serial fallback — gives the most control over timing and avoids picocom's port locking issues.
- **Prompt detection regex:** `r'AH-[0-9a-f]{6}#\s*$'` — matches the `AH-XXXXXX#` pattern. On the SR2024 switch over serial, the prompt may arrive fragmented across multiple reads. A pyserial implementation should accumulate a buffer and regex-match against the whole buffer, not individual reads. SSH doesn't have this problem.
- **Paging:** After sending a command, loop: read until prompt OR `--More--`. On `--More--`, send space and continue. Collect all chunks.
- **Timeouts:** Normal commands: 5–10 seconds. Boot/reset: 120 seconds. Show commands with lots of output: 15 seconds.
- **Inter-command delay:** The SR2024 switch needs ~1–2 seconds between commands over serial to avoid `ttyS0: input overrun` errors. APs are fine with no delay. Over SSH this is not an issue. The MCP server should default to a conservative delay (1s) for serial with an option to reduce for APs.
- **Device registry:** Map device names to connection info (IP for SSH, serial port for console). Example: `{"switch": {"ssh": "192.168.1.237", "serial": "/dev/ttyUSB0"}, "ap230": {"ssh": "192.168.1.242"}}`.
- **Output parsing:** Strip the echoed command (first line), strip the trailing prompt, strip `--More--` artifacts and ANSI escape sequences. Return clean text.
- **Concurrency:** SSH supports concurrent sessions to different devices. Serial is inherently single-threaded per port — queue commands and execute sequentially.

### Output Cleaning

Raw serial output contains artifacts that need stripping:
```
\r\n           — line endings are CRLF
--More--       — paging prompts (followed by spaces that overwrite them)
\x08 (BS)      — backspace characters from --More-- cleanup
AH-XXXXXX#    — trailing prompt
```

Regex for cleaning: strip `--More--\s*`, strip `\x08+\s+\x08+`, strip leading echo of the sent command.

## Current Device Inventory

| Device | Hostname | MAC (mgt0) | Firmware | Switch Port | DHCP IP | Status |
|--------|----------|------------|----------|-------------|---------|--------|
| SR2024 switch | AH-864d00 | 08:ea:44:86:4d:00 | HiveOS 6.5r8 | — | 192.168.1.237 | Factory reset, CAPWAP disabled, saved |
| AP230 | AH-1cea80 | 9c:5d:12:1c:ea:80 | HiveOS 8.1r1 | eth1/1 | 192.168.1.242 | Factory reset, CAPWAP disabled, saved |
| AP130 #1 | AH-b614c0 | 88:5b:dd:b6:14:c0 | HiveOS 6.5r8b | eth1/2 | 192.168.1.226 | Factory reset, CAPWAP disabled, saved |
| AP130 #2 | AH-2d2280 | 88:5b:dd:2d:22:80 | HiveOS 6.5r1b | eth1/3 | 192.168.1.227 | Factory reset, CAPWAP disabled, saved. Older firmware (2015). 1 bad NAND block. |
| MSI laptop | — | 00:e0:4c:2c:62:c0 | — | eth1/4 | 192.168.1.100 (static) | USB ethernet adapter (enx00e04c2c62c0) |

DHCP IPs are from a temporary dnsmasq session and are not persistent. Devices will request new addresses on next boot if a DHCP server is available, or fall back to the 192.168.0.0/16 default subnet.

### Hardware Specs (from boot logs)

| Device | CPU Clock | RAM | Kernel | NAND | PoE Input |
|--------|-----------|-----|--------|------|-----------|
| SR2024 | — | — | Linux (version unknown) | — | N/A |
| AP230 | 1 GHz ARM | 256 MB | Linux 3.16.36 | 512 MB | 802.3at (PoE+) |
| AP130 #1 | 800 MHz ARM | 256 MB | Linux 2.6.36 | 512 MB (0 bad blocks) | PoE (assumed, via switch) |
| AP130 #2 | 800 MHz ARM | 256 MB | Linux 2.6.36 | 511 MB (1 bad block @ 0x13b80000) | PoE (assumed, via switch) |

### Firmware Versions

| Device | HiveOS | Build Date | Notes |
|--------|--------|------------|-------|
| SR2024 | 6.5r8 | Aug 2017 | |
| AP230 | 8.1r1 | Aug 2017 | Higher version than AP130s — different firmware track |
| AP130 #1 | 6.5r8b | Oct 2017 | |
| AP130 #2 | 6.5r1b | Jul 2015 | Significantly older — consider updating to match #1 |

## PoE

The SR2024 **does provide PoE** (802.3at / PoE+). All three APs are successfully powered by the switch. The AP230 boot log confirms `Power Input Detection: POE AT`. No external PoE injectors needed.

## DHCP Behavior

All devices have DHCP enabled by default on mgt0 (VLAN 1). DHCP client details:

| Device | Vendor Class | DHCP Client |
|--------|-------------|-------------|
| SR2024 | `AEROHIVE` | HiveOS built-in |
| AP230 | `AEROHIVE` | HiveOS built-in |
| AP130 #1 | `AEROHIVE` | HiveOS built-in |
| AP130 #2 | `udhcp 0.9.9-pre` | Different DHCP client (older firmware) |

All devices request options 225–231 or option 43 (vendor-specific) — these are for CAPWAP/HiveManager discovery. Harmless when CAPWAP is disabled.
