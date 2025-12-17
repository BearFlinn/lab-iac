# Baseline Machine Setup Guide

This playbook configures the initial baseline setup for **individual machines** - completely independent of Kubernetes. It automatically makes the current DHCP IP static, sets hostname, and installs essential packages.

**Important**: This playbook is designed to work on **one machine at a time**. You do not need all machines online to set up one machine.

## What It Does

1. **Package Installation**: Installs essential utilities (curl, wget, git, vim, htop, net-tools, nfs-common, etc.)
2. **Hostname Configuration**: Sets the hostname and updates /etc/hosts
3. **Static IP Configuration**: Makes the current DHCP IP static (auto-detects network, gateway, netmask)
4. **DNS Configuration**: Sets custom DNS servers
5. **Cluster Hosts File**: Adds all cluster nodes to /etc/hosts for easy communication
6. **System Tweaks**: Disables automatic updates, sets timezone
7. **Optional Firewall**: Can enable and configure ufw firewall

## Key Feature: Auto-Static IP

**The playbook will automatically make whatever IP the machine currently has into a static IP.**

- No need to specify target IPs manually
- Auto-detects: current IP, gateway, subnet mask, network interface
- You can override with `static_ip` variable if you want a specific IP

## Prerequisites

### For Each Target Machine:

1. **OS Installed**: Ubuntu/Debian-based OS (Ubuntu 20.04/22.04, Debian 11/12)
2. **Network Access**: Machine should be accessible via SSH with current DHCP IP
3. **SSH Access**: Password or key-based authentication set up
4. **Sudo Privileges**: User must have sudo/root access

### Initial SSH Setup (if not already done):

```bash
# Copy SSH key to target machine (use current IP)
ssh-copy-id bearf@10.0.0.226

# Test connection
ssh bearf@10.0.0.226
```

## Configuration

### 1. Update Inventory File

Edit `ansible/inventory/all-nodes.yml` and set the current IP for each machine:

```yaml
dell-inspiron-15:
  ansible_host: 10.0.0.226      # Current IP (DHCP or whatever it is now)
  ansible_user: bearf            # SSH username
```

**That's it!** The playbook will automatically:
- Detect the current IP (10.0.0.226)
- Detect the gateway
- Detect the subnet mask
- Configure that IP as static

### 2. Optional: Set Specific Static IP

If you want to change the IP to something else, add `static_ip`:

```yaml
dell-inspiron-15:
  ansible_host: 10.0.0.226      # Current IP where it's accessible NOW
  static_ip: 10.0.0.100          # New IP you want it to have
  ansible_user: bearf
```

### 3. Network Settings (Optional)

Edit network variables in `all-nodes.yml` under `all.vars`:

```yaml
all:
  vars:
    # network_gateway: "10.0.0.1"  # Auto-detected if not specified
    network_dns:                    # Custom DNS servers
      - "8.8.8.8"
      - "8.8.4.4"
    timezone: "America/New_York"    # Your timezone
    enable_firewall: false          # true to enable ufw
```

## Running the Playbook

### Recommended: Use Standalone Inventory (One Machine at a Time)

```bash
cd /home/bearf/Projects/lab-iac

# Setup Dell Inspiron first
ansible-playbook -i ansible/inventory/dell-inspiron-15-standalone.yml \
  ansible/playbooks/baseline-setup.yml -v
```

### For Other Machines:

1. Copy the template:
   ```bash
   cp ansible/inventory/single-machine.yml ansible/inventory/tower-pc-standalone.yml
   ```

2. Edit with the machine's info (hostname, IP, user)

3. Run baseline setup:
   ```bash
   ansible-playbook -i ansible/inventory/tower-pc-standalone.yml \
     ansible/playbooks/baseline-setup.yml -v
   ```

### Advanced: Setup Multiple Machines (if all are online)

```bash
# Only if ALL machines in all-nodes.yml are accessible
ansible-playbook -i ansible/inventory/all-nodes.yml \
  ansible/playbooks/baseline-setup.yml -v
```

## What Happens After Running

The playbook will:
1. ✅ Install essential packages
2. ✅ Set hostname to inventory name (e.g., `dell-inspiron-15`)
3. ✅ Configure the current IP (e.g., 10.0.0.226) as static
4. ✅ Auto-detect and configure gateway, netmask
5. ✅ Set DNS servers
6. ✅ Add all cluster nodes to /etc/hosts
7. ✅ Display summary with all network info

**The IP won't change** - the machine stays at the same IP, but now it's static instead of DHCP.

## After Running Baseline Setup

### 1. Verify Static IP Configuration

```bash
# SSH using the same IP (it didn't change)
ssh bearf@10.0.0.226

# Verify IP is now static
ip addr show

# Check netplan config (Ubuntu 18.04+)
cat /etc/netplan/01-static-ip.yaml

# Test connectivity
ping 10.0.0.1  # Gateway
ping 8.8.8.8   # DNS
```

### 2. Test Ansible Connectivity

```bash
ansible -i ansible/inventory/all-nodes.yml k8s_control_plane -m ping
ansible -i ansible/inventory/all-nodes.yml k8s_workers -m ping
ansible -i ansible/inventory/all-nodes.yml k8s_cluster -m ping
```

## Complete Workflow: Fresh OS to Kubernetes

```bash
# Step 1: Update inventory with current IPs
# Edit ansible/inventory/all-nodes.yml - set ansible_host to current IPs

# Step 2: Test connectivity
ansible -i ansible/inventory/all-nodes.yml k8s_cluster -m ping

# Step 3: Run baseline setup (makes IPs static, sets hostnames, etc.)
ansible-playbook -i ansible/inventory/all-nodes.yml \
  ansible/playbooks/baseline-setup.yml -v

# Step 4: Deploy Kubernetes control plane
ansible-playbook -i ansible/inventory/all-nodes.yml \
  ansible/playbooks/setup-control-plane.yml -v

# Step 5: Join worker nodes (future playbook)
# ansible-playbook -i ansible/inventory/all-nodes.yml \
#   ansible/playbooks/join-workers.yml -v
```

## Examples

### Example 1: Simple Case (Use Current IP as Static)

```yaml
# Inventory
dell-inspiron-15:
  ansible_host: 10.0.0.226
  ansible_user: bearf
```

**Result**: Machine stays at 10.0.0.226, but now it's configured statically.

### Example 2: Change to Different IP

```yaml
# Inventory
dell-inspiron-15:
  ansible_host: 10.0.0.226    # Where it is NOW
  static_ip: 10.0.0.100        # Where you want it to be
  ansible_user: bearf
```

**Result**: Machine changes from 10.0.0.226 to 10.0.0.100. After playbook completes, update `ansible_host` to `10.0.0.100`.

## Troubleshooting

### Check What IP Will Be Used

Run in check mode to see what will happen:

```bash
ansible-playbook -i ansible/inventory/all-nodes.yml \
  ansible/playbooks/baseline-setup.yml \
  --limit dell-inspiron-15 --check -v
```

### Static IP Not Applied

**Netplan systems** (Ubuntu 18.04+):
```bash
# Check netplan config
sudo cat /etc/netplan/01-static-ip.yaml

# Apply manually
sudo netplan apply

# Check status
ip addr show
```

**NetworkManager systems**:
```bash
# Check connection
nmcli connection show

# Check IP
ip addr show
```

### DNS Not Working

```bash
# Check /etc/resolv.conf
cat /etc/resolv.conf

# Test DNS resolution
nslookup google.com
dig google.com
```

### View Current Network Info

Before running the playbook, you can check what Ansible detects:

```bash
ansible -i ansible/inventory/all-nodes.yml dell-inspiron-15 -m setup | grep -A 5 default_ipv4
```

This shows:
- Current IP address
- Gateway
- Interface
- Netmask

## Manual Static IP Configuration (if Ansible fails)

### For netplan systems:

```bash
sudo nano /etc/netplan/01-static-ip.yaml
```

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:  # or your interface name
      dhcp4: no
      addresses:
        - 10.0.0.226/24
      routes:
        - to: default
          via: 10.0.0.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

```bash
sudo netplan apply
```

### For NetworkManager:

```bash
nmcli connection modify <connection-name> \
  ipv4.addresses "10.0.0.226/24" \
  ipv4.gateway "10.0.0.1" \
  ipv4.dns "8.8.8.8 8.8.4.4" \
  ipv4.method manual

nmcli connection up <connection-name>
```

## Next Steps

After baseline setup is complete:
1. Proceed with [Kubernetes control plane setup](README-CONTROL-PLANE.md)
2. Configure storage on tower-pc
3. Deploy monitoring on msi-laptop
4. Join worker nodes to the cluster
