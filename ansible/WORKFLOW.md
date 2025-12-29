# Cluster Setup Workflow

This document outlines the step-by-step process to set up your Kubernetes cluster from scratch.

## Phase 0: Individual Machine Baseline Setup

Set up each machine **individually** before attempting cluster setup. This ensures each machine is properly configured with static IP, hostname, and essential packages.

### Step 1: Dell Inspiron 15 (Control Plane)

```bash
# Test connectivity
ansible -i ansible/inventory/control-plane.yml all -m ping

# Run baseline setup
ansible-playbook -i ansible/inventory/control-plane.yml \
  ansible/playbooks/baseline-setup.yml -v

# Verify
ssh bearf@10.0.0.226
hostname  # Should show: dell-inspiron-15
ip addr   # Verify static IP
exit
```

### Step 2: Other Machines (One at a time)

For each remaining machine (tower-pc, msi-laptop):

1. **Create a temporary single-host inventory**:
   ```bash
   # Copy the template to /tmp/
   cp ansible/inventory/single-host/template.yml /tmp/tower-pc.yml
   ```

2. **Edit the inventory file** with actual values:
   ```bash
   # Edit /tmp/tower-pc.yml and update:
   # - HOSTNAME -> tower-pc
   # - ansible_host: 10.0.0.XXX -> actual IP (e.g., 10.0.0.249)
   # - ansible_user: bearf (or your username)
   ```

3. **Copy SSH key** to the machine:
   ```bash
   ssh-copy-id bearf@10.0.0.249
   ```

4. **Run baseline setup**:
   ```bash
   ansible-playbook -i /tmp/tower-pc.yml \
     ansible/playbooks/baseline-setup.yml -v
   ```

5. **Verify** the machine is set up correctly:
   ```bash
   ssh bearf@10.0.0.249
   hostname  # Should show correct hostname
   ip addr   # Verify static IP
   exit
   ```

6. **Clean up temporary file**:
   ```bash
   rm /tmp/tower-pc.yml
   ```

See `ansible/inventory/single-host/README.md` for more details on single-host inventories.

### Step 3: Update All-Nodes Inventory

After all machines are set up individually, update `ansible/inventory/all-nodes.yml` with the actual IP addresses of all machines.

### Step 4: Verify All Machines

```bash
# Test connectivity to all machines
ansible -i ansible/inventory/all-nodes.yml all -m ping

# Optionally: Add all machines to each other's /etc/hosts
ansible-playbook -i ansible/inventory/all-nodes.yml \
  ansible/playbooks/baseline-setup.yml \
  --tags hosts -v
```

## Phase 1: Kubernetes Control Plane Setup

Once all machines are baseline-configured:

```bash
# Deploy Kubernetes control plane on Dell Inspiron
ansible-playbook -i ansible/inventory/control-plane.yml \
  ansible/playbooks/setup-control-plane.yml -v

# Verify cluster is running
ssh bearf@10.0.0.226
kubectl get nodes
kubectl get pods -A
exit
```

## Phase 2: Join Worker Nodes

### Automated setup (recommended):
```bash
# Join both worker nodes to the cluster in one command
ansible-playbook -i ansible/inventory/all-nodes.yml \
  ansible/playbooks/setup-workers.yml
```

The playbook will:
- Install Kubernetes prerequisites on worker nodes
- Generate join command from control plane
- Join workers to cluster
- Apply node labels per ARCHITECTURE.md
- Verify cluster health

### Manual setup (if needed):
If you prefer to join nodes manually, the join command is saved to `/tmp/k8s-join-command.sh` on your local machine after running the control plane setup.

## Phase 3: Configure Node Labels

Node labels are now automatically applied by the setup-workers.yml playbook per ARCHITECTURE.md.

If you need to update labels manually:
```bash
kubectl label node msi-laptop node-role.kubernetes.io/monitoring=true workload=observability --overwrite
kubectl label node tower-pc node-role.kubernetes.io/storage=true workload=storage --overwrite
```

## Phase 4: Storage, Monitoring, etc.

Follow ARCHITECTURE.md for subsequent phases.

---

## Quick Reference

### Single Machine Setup (Baseline Only)
```bash
# 1. Create temporary inventory from template
cp ansible/inventory/single-host/template.yml /tmp/my-host.yml

# 2. Edit /tmp/my-host.yml with actual values (hostname, IP, username)

# 3. Copy SSH key
ssh-copy-id bearf@IP_ADDRESS

# 4. Run baseline
ansible-playbook -i /tmp/my-host.yml \
  ansible/playbooks/baseline-setup.yml -v

# 5. Clean up
rm /tmp/my-host.yml
```

For control plane, you can use `ansible/inventory/control-plane.yml` directly.

### What baseline-setup.yml Does (Per Machine)
- ✅ Sets hostname
- ✅ Configures static IP (auto-detects current IP and network settings)
- ✅ Installs essential packages
- ✅ Sets timezone
- ✅ Disables automatic updates
- ✅ Does **NOT** install Kubernetes (that's separate)

### What baseline-setup.yml Does NOT Do
- ❌ Install Kubernetes packages
- ❌ Join nodes to cluster
- ❌ Configure CNI networking
- ❌ Require all nodes to be online

This keeps baseline setup completely independent from Kubernetes setup!
