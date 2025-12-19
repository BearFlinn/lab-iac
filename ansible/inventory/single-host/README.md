# Single-Host Inventory Setup

This directory contains a template for creating single-host inventory files for individual machine setup.

## Why Use Single-Host Inventories?

When performing initial baseline setup on a new machine, you typically:
- Only need to target one host at a time
- Don't want to affect other machines in the cluster
- May not have the machine added to the main cluster inventory yet

Single-host inventories provide a clean, isolated way to set up individual machines.

## Quick Start

### 1. Copy the Template

```bash
cp ansible/inventory/single-host/template.yml /tmp/my-host.yml
```

**Note:** Create the inventory in `/tmp/` or another temporary location. These single-host files are temporary and shouldn't be committed to the repository.

### 2. Edit the File

Open `/tmp/my-host.yml` and customize:

```yaml
all:
  hosts:
    tower-pc:  # Replace HOSTNAME with actual hostname
      ansible_host: 10.0.0.249  # Replace with actual IP
      ansible_connection: ssh
      ansible_user: bearf  # Replace with actual username
```

### 3. Run Baseline Setup

```bash
ansible-playbook -i /tmp/my-host.yml ansible/playbooks/baseline-setup.yml
```

This will:
- Configure the host with baseline settings
- Set up networking, users, packages, etc.
- Prepare the machine for cluster operations

### 4. Add to Cluster Inventory

After baseline setup completes successfully, add the host to `ansible/inventory/all-nodes.yml`:

```yaml
k8s_workers:  # or k8s_control_plane
  hosts:
    tower-pc:
      ansible_host: 10.0.0.249
      ansible_connection: ssh
      ansible_user: bearf
      # Add full hardware specs, roles, etc.
```

## Example Workflows

### Setting Up a New Worker Node

```bash
# 1. Create inventory
cp ansible/inventory/single-host/template.yml /tmp/new-worker.yml

# 2. Edit /tmp/new-worker.yml
#    - Set hostname: new-worker
#    - Set ansible_host: 10.0.0.100
#    - Set ansible_user: bearf

# 3. Run baseline setup
ansible-playbook -i /tmp/new-worker.yml ansible/playbooks/baseline-setup.yml

# 4. Add to ansible/inventory/all-nodes.yml under k8s_workers

# 5. Clean up temporary file
rm /tmp/new-worker.yml
```

### Re-running Baseline Setup on Existing Host

If you need to re-run baseline setup on a host already in the cluster:

```bash
# Option 1: Use all-nodes.yml with --limit
ansible-playbook -i ansible/inventory/all-nodes.yml \
  ansible/playbooks/baseline-setup.yml --limit tower-pc

# Option 2: Create temporary single-host inventory
cp ansible/inventory/single-host/template.yml /tmp/tower-pc.yml
# Edit /tmp/tower-pc.yml with tower-pc details
ansible-playbook -i /tmp/tower-pc.yml ansible/playbooks/baseline-setup.yml
```

## Template Variables Reference

### Required Variables

- `HOSTNAME`: Replace with the actual hostname of the machine
- `ansible_host`: The IP address of the target machine
- `ansible_user`: SSH username for Ansible connections

### Optional Variables

- `static_ip`: Uncomment to set a specific static IP address
- `network_dns`: DNS servers (default: Google DNS)
- `timezone`: System timezone (default: America/New_York)
- `enable_firewall`: Whether to enable UFW firewall (default: false)
- `add_hosts_file`: Whether to add other hosts to /etc/hosts (default: false)

## Important Notes

1. **Don't commit single-host inventories**: These are temporary files for setup. The source of truth is `all-nodes.yml`.

2. **Use `/tmp/` for temporary inventories**: Keeps them separate from the repository.

3. **Clean up after use**: Delete temporary inventory files once the host is added to `all-nodes.yml`.

4. **For cluster operations**: Always use `ansible/inventory/all-nodes.yml`, not single-host inventories.

## Troubleshooting

### "Host unreachable" Error

Check that:
- The IP address in `ansible_host` is correct
- SSH is enabled on the target machine
- You can manually SSH: `ssh bearf@10.0.0.XXX`

### "Permission denied" Error

Check that:
- The `ansible_user` is correct
- SSH key authentication is set up
- The user has sudo permissions

### Variables Not Applied

Ensure you're using the `-i` flag:
```bash
ansible-playbook -i /tmp/my-host.yml ansible/playbooks/baseline-setup.yml
```

## See Also

- `ansible/WORKFLOW.md`: Complete setup workflow documentation
- `ansible/README-BASELINE-SETUP.md`: Baseline setup playbook details
- `ansible/inventory/all-nodes.yml`: Cluster master inventory
