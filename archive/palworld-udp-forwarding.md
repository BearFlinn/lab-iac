# Palworld Server UDP Port Forwarding

## Overview

This document describes the UDP port forwarding configuration on `proxy-vps` to route Palworld game traffic to the game server on the NetBird network.

## Configuration Details

- **Public Endpoint**: `*.gameservers.bearflinn.com:8211/udp`
- **Target Server**: `100.96.46.7:8211` (NetBird network)
- **Protocol**: UDP
- **VPS Public IP**: `<VPS_PUBLIC_IP>`
- **VPS NetBird IP**: `100.96.6.137`

## Components Configured

### 1. IP Forwarding

IP forwarding was enabled to allow the VPS to route packets between interfaces:

```bash
# Temporary enable
echo 1 > /proc/sys/net/ipv4/ip_forward

# Persistent configuration in /etc/sysctl.conf
net.ipv4.ip_forward=1
```

### 2. Firewall Rules

Port 8211/UDP was opened in the firewall:

```bash
# UFW was removed during iptables-persistent installation
# Firewall rules are now managed directly via iptables
# Port 8211/UDP is allowed through the saved iptables rules
```

### 3. NAT Rules

Two iptables NAT rules were configured:

#### PREROUTING (DNAT)
Redirects incoming UDP traffic on port 8211 to the NetBird server:

```bash
iptables -t nat -A PREROUTING -p udp --dport 8211 -j DNAT --to-destination 100.96.46.7:8211
```

#### POSTROUTING (MASQUERADE)
Masquerades the source IP so return traffic comes back through the VPS:

```bash
iptables -t nat -A POSTROUTING -p udp -d 100.96.46.7 --dport 8211 -j MASQUERADE
```

### 4. Persistence

Rules are automatically saved and restored on reboot via `netfilter-persistent`:

- **Service**: `netfilter-persistent.service`
- **Rules file**: `/etc/iptables/rules.v4`
- **Auto-start**: Enabled via systemd

## DNS Configuration

To complete the setup, DNS records need to point to the VPS public IP:

```dns
*.gameservers.bearflinn.com.  IN  A  <VPS_PUBLIC_IP>
```

## Testing

### From the Internet

Players can connect to the Palworld server using:

```
gameservers.bearflinn.com:8211
```

Or any subdomain like:

```
palworld.gameservers.bearflinn.com:8211
```

### Verify Port Forwarding

Check that packets are being forwarded:

```bash
# On proxy-vps
sudo iptables -t nat -L -n -v

# Look for packet/byte counts increasing on the DNAT and MASQUERADE rules
```

### Monitor Traffic

```bash
# Watch NAT table statistics
watch -n1 'sudo iptables -t nat -L -n -v'

# Monitor connection tracking
sudo conntrack -L | grep 8211
```

## Troubleshooting

### Check if IP forwarding is enabled

```bash
cat /proc/sys/net/ipv4/ip_forward
# Should output: 1
```

### Verify NAT rules are loaded

```bash
sudo iptables -t nat -L -n -v --line-numbers
```

### Check NetBird connectivity

```bash
# Ping the target server
ping -c 3 100.96.46.7

# Check NetBird status
sudo netbird status
```

### Verify firewall isn't blocking

```bash
# Check iptables INPUT chain
sudo iptables -L INPUT -n -v | grep 8211

# Test UDP connectivity from another host
nc -u <VPS_PUBLIC_IP> 8211
```

### Check saved rules will persist

```bash
# View saved rules
sudo cat /etc/iptables/rules.v4 | grep 8211

# Manually save current rules if needed
sudo netfilter-persistent save
```

## Removing the Configuration

If you need to remove this port forwarding:

```bash
# Remove the NAT rules
sudo iptables -t nat -D PREROUTING -p udp --dport 8211 -j DNAT --to-destination 100.96.46.7:8211
sudo iptables -t nat -D POSTROUTING -p udp -d 100.96.46.7 --dport 8211 -j MASQUERADE

# Save the updated rules
sudo netfilter-persistent save

# Optionally disable IP forwarding if not needed for other services
sudo sysctl -w net.ipv4.ip_forward=0
# And remove from /etc/sysctl.conf
```

## Notes

- This is a temporary configuration for friends to play Palworld
- The NetBird network (100.96.0.0/16) provides secure connectivity between the VPS and game server
- All game traffic is forwarded directly; no TLS termination or HTTP proxying involved
- UFW was replaced with direct iptables management during iptables-persistent installation
- The existing UFW rules were preserved in the iptables chains

## Configuration Date

- **Configured**: 2025-12-24
- **Configured By**: Claude Code
- **Server**: proxy-vps-3
