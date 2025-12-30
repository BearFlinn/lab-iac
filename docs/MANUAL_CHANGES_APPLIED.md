# Manual Changes Applied During K8s Migration

This document tracks all manual configuration changes made during the Kubernetes migration that have since been automated.

## Overview

During the initial migration (Phase 4), several manual changes were made to get things working quickly. These have all been automated and documented here for reference.

---

## 1. NetBird Firewall Fix (K8s Control Plane)

### Problem
NetBird's default nftables rules only allow ESTABLISHED/RELATED connections in the forward chain, blocking NEW TCP connections (like HTTP requests) from NetBird peers to Kubernetes NodePorts.

### Manual Fix Applied
```bash
# On k8s-control node (dell-inspiron-15):
sudo nft add rule ip netbird netbird-rt-fwd ip saddr @nb0000002 accept  # VPS
sudo nft add rule ip netbird netbird-rt-fwd ip saddr @nb0000056 accept
sudo nft add rule ip netbird netbird-rt-fwd ip saddr @nb0000058 accept
sudo nft add rule ip netbird netbird-rt-fwd ip saddr @nb0000110 accept
```

### Automated Solution
**Script**: `scripts/fix-netbird-k8s-forwarding.sh`
**Playbook**: `ansible/playbooks/fix-netbird-k8s.yml`

```bash
# Run the script directly:
sudo ./scripts/fix-netbird-k8s-forwarding.sh

# Or use Ansible:
ansible-playbook ansible/playbooks/fix-netbird-k8s.yml
```

**Features**:
- Idempotent (safe to run multiple times)
- Creates systemd service for persistence across reboots
- Saves rules to `/etc/nftables.d/netbird-k8s.nft`
- Verifies NetBird is installed before proceeding

---

## 2. VPS Caddy Configuration

### Problem
VPS needed Caddyfile configuration to route traffic to Kubernetes services via NetBird tunnel.

### Manual Fix Applied
```bash
# Manually created and deployed Caddyfile with:
# - K8s service routes (landing, zork, resume, coaching, family)
# - Preserved existing routes (gin-house, test)
# - Routing to NetBird IP: 100.96.94.27:30487
```

### Automated Solution
**Template**: `ansible/templates/Caddyfile-k8s-netbird.j2`
**Playbook**: `ansible/playbooks/configure-vps-k8s-routes.yml`

```bash
# Deploy via Ansible:
ansible-playbook -i ansible/inventory/proxy-vps.yml \
  ansible/playbooks/configure-vps-k8s-routes.yml
```

**Configuration Variables**:
```yaml
# In ansible/playbooks/configure-vps-k8s-routes.yml
k8s_netbird_ip: "100.96.94.27"
k8s_ingress_nodeport: "30487"

k8s_services:
  - domain: "landing.bearflinn.com"
  - domain: "zork.bearflinn.com"
  - domain: "resume.bearflinn.com"
  - domain: "coaching.bearflinn.com"
  - domain: "family.bearflinn.com"

existing_services:
  - domain: "gin-house.bearflinn.com"
    backend: "100.96.217.175:8123"
  - domain: "test.bearflinn.com"
    type: "static"
```

---

## 3. VPS Log File Permissions

### Problem
Caddy couldn't create `/var/log/caddy/k8s-access.log` due to missing parent directory or permissions.

### Manual Fix Applied
```bash
# On VPS:
sudo touch /var/log/caddy/k8s-access.log
sudo chown caddy:caddy /var/log/caddy/k8s-access.log
sudo chmod 644 /var/log/caddy/k8s-access.log
```

### Automated Solution
Now handled by playbook `ansible/playbooks/configure-vps-k8s-routes.yml`:
- Creates log directory with proper ownership
- Creates log file with proper permissions
- Ensures idempotency

---

## 4. GitHub Runner RBAC Permissions

### Problem
GitHub Actions runner service account couldn't create namespaces or deploy services cluster-wide.

### Manual Fix Applied
```bash
kubectl apply -f /tmp/github-runner-rbac.yaml
```

### Automated Solution
**Manifest**: `k8s-manifests/github-runner/rbac.yaml`

```bash
# Apply via kubectl:
kubectl apply -f k8s-manifests/github-runner/rbac.yaml
```

**Permissions Granted**:
- Create/manage namespaces
- Deploy workloads (deployments, statefulsets)
- Manage services, configmaps, secrets, PVCs
- Manage ingress resources
- View pods and logs

---

## 5. Domain Updates (All Application Repositories)

### Problem
All Helm charts used `grizzly-endeavors.com` domain, needed to be `bearflinn.com`.

### Manual Fix Applied
Used `Edit` tool to update values.yaml and values.yaml.example files in:
- landing-page
- zork
- resume-site
- coaching-website
- family-dashboard

### Automated Solution
Changes committed to git repositories:
```bash
# View commit in each repo:
cd /home/bearf/Projects/landing-page && git log --oneline -1
cd /home/bearf/Projects/zork && git log --oneline -1
cd /home/bearf/Projects/resume-site && git log --oneline -1
cd /home/bearf/Projects/coaching-website && git log --oneline -1
cd /home/bearf/Projects/family-dashboard && git log --oneline -1
```

---

## Summary Table

| Component | Manual Change | Automation | Location |
|-----------|--------------|------------|----------|
| NetBird Firewall | nft commands | Script + Playbook | `scripts/fix-netbird-k8s-forwarding.sh` |
| VPS Caddy | Edited Caddyfile | Template + Playbook | `ansible/playbooks/configure-vps-k8s-routes.yml` |
| Log Permissions | touch/chown | Playbook task | Included in Caddy playbook |
| Runner RBAC | kubectl apply | Manifest | `k8s-manifests/github-runner/rbac.yaml` |
| Domains | Edit files | Git commits | Each app repository |

---

## Testing the Automation

### Verify NetBird Fix
```bash
# On k8s-control:
sudo nft list chain ip netbird netbird-rt-fwd | grep "ip saddr @nb"

# Should see rules for nb0000002, nb0000056, nb0000058, nb0000110
```

### Verify VPS Routing
```bash
# From VPS:
curl -H "Host: landing.bearflinn.com" http://100.96.94.27:30487

# Should return landing page HTML
```

### Verify RBAC
```bash
# Try creating a namespace as the runner:
kubectl auth can-i create namespaces --as=system:serviceaccount:actions-runner-system:github-runner
# Should return "yes"
```

---

## Future Improvements

1. **Ansible Inventory Integration**: Move VPS variables to inventory file instead of hardcoding in playbook
2. **NetBird Peer Discovery**: Auto-discover NetBird peer IPs instead of hardcoding set numbers
3. **K8s Ingress NodePort Discovery**: Query k8s for ingress NodePort instead of hardcoding
4. **Caddy Route Validation**: Add tests to verify routes are working after deployment

---

## References

- Migration Plan: `docs/kubernetes-migration-plan.md`
- Remaining Steps: `docs/REMAINING_MIGRATION_STEPS.md`
- NetBird Documentation: https://docs.netbird.io/
- Caddy Documentation: https://caddyserver.com/docs/
