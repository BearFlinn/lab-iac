# Operational Runbooks

This document contains operational procedures, troubleshooting guides, and recovery procedures for the Kubernetes cluster.

## Common Operations

### Check Cluster Health

```bash
# Node status
kubectl get nodes -o wide

# All pods across namespaces
kubectl get pods -A

# System component status
kubectl get componentstatuses

# Resource usage by node
kubectl top nodes

# Resource usage by pods
kubectl top pods -A
```

### Access Cluster

**From local machine:**
```bash
export KUBECONFIG=~/.kube/lab-k8s-config
kubectl get nodes
```

**Direct SSH to control plane:**
```bash
ssh bearf@10.0.0.226
kubectl get nodes
```

### View Application Logs

```bash
# Deployment logs
kubectl logs deployment/app-name

# Follow logs in real-time
kubectl logs -f deployment/app-name

# Previous container logs (if crashed)
kubectl logs deployment/app-name --previous

# All pods matching a label
kubectl logs -l app=app-name --all-containers
```

### Restart Deployments

```bash
# Rolling restart (maintains availability)
kubectl rollout restart deployment/app-name

# Check rollout status
kubectl rollout status deployment/app-name

# Rollback if needed
kubectl rollout undo deployment/app-name
```

### Scale Applications

```bash
# Scale deployment
kubectl scale deployment/app-name --replicas=3

# Scale to zero (stop)
kubectl scale deployment/app-name --replicas=0
```

## Troubleshooting

### Pod Not Starting

**Symptoms:** Pod stuck in Pending, ContainerCreating, or CrashLoopBackOff

**Diagnosis:**
```bash
# Check pod status and events
kubectl describe pod <pod-name>

# Check pod logs
kubectl logs <pod-name>

# Check node resources
kubectl describe node <node-name> | grep -A 10 "Allocated resources"
```

**Common Causes:**

1. **Image pull errors:**
   ```bash
   # Verify registry is accessible
   curl http://10.0.0.226:32346/v2/_catalog

   # Check image exists
   curl http://10.0.0.226:32346/v2/app-name/tags/list
   ```

2. **Insufficient resources:**
   ```bash
   # Check node capacity
   kubectl describe nodes | grep -A 5 "Allocated resources"
   ```

3. **Volume mount issues:**
   ```bash
   # Check PVC status
   kubectl get pvc
   kubectl describe pvc <pvc-name>
   ```

### Ingress Not Working

**Symptoms:** Domain returns 404, 502, or connection refused

**Diagnosis:**
```bash
# Check ingress resource
kubectl get ingress -A
kubectl describe ingress <ingress-name>

# Check NGINX Ingress Controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Test from control plane
curl -H "Host: app.bearflinn.com" http://localhost:30487
```

**Fixes:**

1. **Wrong service name/port:**
   ```bash
   # Verify service exists
   kubectl get svc
   kubectl describe svc <service-name>
   ```

2. **Ingress class missing:**
   ```yaml
   spec:
     ingressClassName: nginx  # Must be specified
   ```

### Database Connection Issues

**Symptoms:** Application cannot connect to PostgreSQL

**Diagnosis:**
```bash
# Check database pod
kubectl get statefulset app-name-db
kubectl logs statefulset/app-name-db

# Check database service
kubectl get svc app-name-db

# Test connectivity from app pod
kubectl exec -it deployment/app-name -- nc -zv app-name-db 5432
```

**Fixes:**

1. **Wrong connection string:**
   - Host should be the service name: `app-name-db`
   - Port is typically 5432

2. **Database not ready:**
   ```bash
   # Check if database is accepting connections
   kubectl exec -it statefulset/app-name-db -- pg_isready
   ```

### Calico BGP Peering Failures

**Symptoms:** Calico pods show `0/1 Running`, BGP not established

**Diagnosis:**
```bash
# Check Calico pods
kubectl get pods -n kube-system -l k8s-app=calico-node

# Check which IP Calico detected
kubectl logs -n kube-system -l k8s-app=calico-node | grep "Using autodetected"

# Check BGP peer status
kubectl exec -it -n kube-system $(kubectl get pods -n kube-system -l k8s-app=calico-node -o name | head -1) -- birdcl show protocols
```

**Fix:** Calico IP autodetection may select wrong interface (e.g., VPN tunnel instead of LAN)

```bash
# Verify patch is applied
kubectl get ds calico-node -n kube-system -o yaml | grep -A5 "IP_AUTODETECTION_METHOD"

# Force pod restart
kubectl delete pods -n kube-system -l k8s-app=calico-node
```

### NetBird VPN Forwarding Issues

**Symptoms:** Traffic from VPS cannot reach K8s services through NetBird

**Diagnosis:**
```bash
# On k8s-control node, check nftables rules
ssh bearf@10.0.0.226
sudo nft list chain ip netbird netbird-rt-fwd
```

**Fix:**
```bash
# Run the automated fix
ansible-playbook ansible/playbooks/fix-netbird-k8s.yml

# Or manually
sudo ./scripts/fix-netbird-k8s-forwarding.sh
```

The fix adds accept rules for NetBird peer sets to allow NEW connections, not just ESTABLISHED.

### GitHub Actions Runner Issues

**Symptoms:** Jobs stuck in queued, runner not appearing in GitHub

**Diagnosis:**
```bash
# Check controller
kubectl get pods -n actions-runner-system
kubectl logs -n actions-runner-system deployment/actions-runner-controller-controller-manager

# Check runners
kubectl get runners -n actions-runner-system
kubectl describe runners -n actions-runner-system
```

**Fixes:**

1. **Authentication issues:**
   ```bash
   # Verify secret exists
   kubectl get secret -n actions-runner-system controller-manager -o yaml
   ```

2. **RBAC permissions:**
   ```bash
   # Reapply RBAC
   kubectl apply -f kubernetes/github-runner/rbac.yaml
   ```

### Container Registry Unavailable

**Symptoms:** Image push/pull fails

**Diagnosis:**
```bash
# Check registry pod
kubectl get pods -n registry
kubectl logs -n registry deployment/docker-registry

# Test registry API
curl http://10.0.0.226:32346/v2/_catalog
```

**Fixes:**

1. **Registry pod down:**
   ```bash
   kubectl delete pod -n registry -l app=docker-registry
   ```

2. **Storage full:**
   ```bash
   kubectl exec -n registry deployment/docker-registry -- df -h /var/lib/registry
   ```

## Recovery Procedures

### Node Recovery

**If a node becomes unreachable:**

```bash
# Check node status
kubectl get nodes

# If NotReady, check on the node via SSH (if possible)
ssh bearf@<node-ip>
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 50

# Restart kubelet
sudo systemctl restart kubelet
```

**If node needs to be drained:**
```bash
# Drain node (evict pods)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Perform maintenance...

# Uncordon node (allow scheduling)
kubectl uncordon <node-name>
```

### Control Plane Recovery

**If API server is unresponsive:**

```bash
# SSH to control plane
ssh bearf@10.0.0.226

# Check control plane components
sudo crictl ps | grep -E "kube-apiserver|etcd|kube-controller|kube-scheduler"

# Restart kubelet (will restart static pods)
sudo systemctl restart kubelet

# Check component logs
sudo crictl logs <container-id>
```

### Reset and Rebuild Cluster

**Last resort - destroys cluster state:**

```bash
# On each node
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
sudo rm -rf ~/.kube

# Then re-run cluster setup
ansible-playbook -i ansible/inventory/control-plane.yml \
  ansible/playbooks/setup-control-plane.yml -v
```

### Database Recovery

**PostgreSQL pod crashed:**

```bash
# Check pod status
kubectl get statefulset app-name-db
kubectl describe pod app-name-db-0

# Check logs
kubectl logs app-name-db-0

# If PVC is intact, just delete pod (StatefulSet recreates)
kubectl delete pod app-name-db-0
```

**Restore from backup (if available):**
```bash
# Copy backup into pod
kubectl cp backup.sql app-name-db-0:/tmp/

# Restore
kubectl exec -it app-name-db-0 -- psql -U postgres -d database_name -f /tmp/backup.sql
```

## VPS Proxy Operations

### Check Caddy Status

```bash
ssh -p 2222 bearf@proxy-vps

# Service status
sudo systemctl status caddy

# View logs
sudo tail -f /var/log/caddy/access.log
sudo journalctl -u caddy -f
```

### Update Caddy Configuration

```bash
# Validate config before applying
sudo caddy validate --config /etc/caddy/Caddyfile

# Reload configuration
sudo systemctl reload caddy
```

### TLS Certificate Issues

```bash
# Check certificate
echo | openssl s_client -servername app.bearflinn.com \
  -connect app.bearflinn.com:443 2>/dev/null | \
  openssl x509 -noout -dates

# Force certificate renewal (Caddy handles automatically)
sudo systemctl restart caddy
```

## Automation Scripts

### Automated Fixes Available

| Issue | Script/Playbook |
|-------|-----------------|
| NetBird K8s forwarding | `scripts/fix-netbird-k8s-forwarding.sh` |
| NetBird K8s forwarding | `ansible/playbooks/fix-netbird-k8s.yml` |
| VPS K8s routes | `ansible/playbooks/configure-vps-k8s-routes.yml` |
| Insecure registry config | `ansible/playbooks/configure-registry.yml` |

### Running Ansible Playbooks

```bash
cd /home/bearf/Projects/lab-iac

# With vault password (if secrets needed)
ansible-playbook -i ansible/inventory/proxy-vps.yml \
  ansible/playbooks/setup-proxy-vps.yml \
  --vault-password-file .vault_pass -v

# Dry run (check mode)
ansible-playbook -i ansible/inventory/all-nodes.yml \
  ansible/playbooks/baseline-setup.yml --check -v
```

## Monitoring Checks

### Quick Health Check Script

```bash
#!/bin/bash
echo "=== Node Status ==="
kubectl get nodes

echo -e "\n=== Failing Pods ==="
kubectl get pods -A | grep -v Running | grep -v Completed

echo -e "\n=== Resource Usage ==="
kubectl top nodes

echo -e "\n=== Ingress Status ==="
kubectl get ingress -A

echo -e "\n=== PVC Status ==="
kubectl get pvc -A
```

### Critical Services to Monitor

| Service | Check Command |
|---------|---------------|
| API Server | `kubectl get --raw='/healthz'` |
| Ingress Controller | `kubectl get pods -n ingress-nginx` |
| Container Registry | `curl http://10.0.0.226:32346/v2/_catalog` |
| GitHub Runners | `kubectl get runners -n actions-runner-system` |

## Contacts and Escalation

This is a personal lab environment. For issues:

1. Check this runbook
2. Check relevant documentation in `/docs`
3. Check Kubernetes and component documentation online
4. Review recent changes in git history
