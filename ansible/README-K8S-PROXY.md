# Kubernetes Cluster Proxy Setup Guide

This guide covers configuring a VPS to act as a reverse proxy for your Kubernetes cluster, enabling external access to both the K8s API server and ingress-based applications.

## Overview

The proxy setup provides:

- **K8s API Server Access**: External kubectl access to your cluster via a secure proxy
- **Application Ingress**: HTTP/HTTPS proxy to K8s ingress services
- **Automatic TLS**: Let's Encrypt certificates for all domains
- **Wildcard Subdomains**: Support for dynamic application routing
- **Security**: HSTS headers, secure TLS configuration, firewall rules

## Architecture

```
Internet
    ↓
VPS (bearflinn.com, *.bearflinn.com)
    ├─ Port 80  → Redirect to HTTPS
    ├─ Port 443 → Caddy Web Server
    │   ├─ api.bearflinn.com → 10.0.0.226:6443 (K8s API)
    │   ├─ app.bearflinn.com → nginx-ingress-controller (K8s)
    │   └─ *.bearflinn.com → catch-all (K8s ingress)
    └─ Port 2222 → SSH

Local Network (10.0.0.0/24)
    ├─ 10.0.0.226 - dell-inspiron-15 (K8s Control Plane)
    ├─ 10.0.0.177 - msi-laptop (K8s Worker)
    └─ 10.0.0.249 - tower-pc (K8s Worker)
```

## Prerequisites

### On VPS
- Ubuntu 22.04 LTS or similar
- SSH access on port 2222
- `ansible` installed on control machine
- SSH key-based authentication

### On Local Network
- K8s cluster running at 10.0.0.226:6443
- Network connectivity between VPS and local K8s cluster (can be via VPN or direct if on same network)

### DNS Configuration
- `bearflinn.com` → VPS IP (A record)
- `*.bearflinn.com` → VPS IP (Wildcard CNAME or A record)

## Setup Steps

### Step 1: Configure Inventory

The proxy-vps inventory is already configured in `ansible/inventory/proxy-vps.yml`:

```yaml
k8s_api_server: "10.0.0.226:6443"
enable_k8s_proxy: true

k8s_proxy_routes:
  - domain: "api.bearflinn.com"
    type: "k8s_api"
    backend: "{{ k8s_api_server }}"
    skip_verify: true  # For self-signed K8s certs

  - domain: "app.bearflinn.com"
    type: "k8s_ingress"
    backend_service: "app-service"
    backend_namespace: "default"
    backend_port: 80

  - domain: "*.bearflinn.com"
    type: "k8s_ingress"
    backend_service: "ingress-nginx-controller"
    backend_namespace: "ingress-nginx"
    backend_port: 80
```

**Customize for your setup:**
- Update `k8s_api_server` to your K8s control plane IP
- Update domain names to match your DNS
- Add additional proxy routes as needed
- Set `skip_verify: false` if you have valid K8s API certificates

### Step 2: Run VPS Setup (if not already done)

```bash
cd /home/bearf/Projects/lab-iac

# Initial VPS setup with Caddy
ansible-playbook -i ansible/inventory/proxy-vps.yml \
  ansible/playbooks/setup-proxy-vps.yml -v
```

### Step 3: Deploy K8s Proxy Configuration

```bash
# Deploy K8s proxy routes
ansible-playbook -i ansible/inventory/proxy-vps.yml \
  ansible/playbooks/setup-k8s-proxy.yml -v
```

Or skip the general proxy setup and only configure K8s proxy:

```bash
ansible-playbook -i ansible/inventory/proxy-vps.yml \
  ansible/playbooks/setup-k8s-proxy.yml --tags k8s_proxy -v
```

## Proxy Route Types

### K8s API Server Route

Routes external requests to the Kubernetes API server:

```yaml
- domain: "api.bearflinn.com"
  type: "k8s_api"
  backend: "10.0.0.226:6443"
  skip_verify: true  # Set to false for valid certificates
```

**Features:**
- Supports TLS certificate validation
- Preserves Authorization headers for kubeconfig
- WebSocket support for kubectl exec/attach
- X-Forwarded headers for audit logging

### K8s Ingress Route

Routes external requests to Kubernetes Ingress services:

```yaml
- domain: "app.bearflinn.com"
  type: "k8s_ingress"
  backend_service: "app-service"
  backend_namespace: "default"
  backend_port: 80
```

**Features:**
- Service discovery via DNS (.svc.cluster.local)
- Preserves HTTP headers for proper routing
- WebSocket support for real-time applications
- Health check endpoints (/healthz)
- Load balancing across replicas

### Wildcard Route

Catch-all for any subdomain:

```yaml
- domain: "*.bearflinn.com"
  type: "k8s_ingress"
  backend_service: "ingress-nginx-controller"
  backend_namespace: "ingress-nginx"
  backend_port: 80
```

Routes to your nginx-ingress-controller for dynamic application routing.

## Usage Examples

### Example 1: Access K8s API via Proxy

Configure your kubeconfig:

```bash
# Export the proxy certificate (if needed)
scp -P 2222 bearf@proxy-vps:/etc/caddy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/api.bearflinn.com/api.bearflinn.com.crt ~/k8s-api-cert.pem

# Update kubeconfig
kubectl config set-cluster my-lab --server=https://api.bearflinn.com --certificate-authority=~/k8s-api-cert.pem
kubectl config set-context my-lab --cluster=my-lab --user=my-user

# Test access
kubectl --context=my-lab get nodes
```

### Example 2: Deploy Application via Ingress

1. Deploy your application in K8s:

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: my-app
spec:
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 80
EOF
```

2. Create an Ingress resource:

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: default
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.bearflinn.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
EOF
```

3. Add proxy route to inventory (optional for nginx-ingress catch-all):

```yaml
- domain: "myapp.bearflinn.com"
  type: "k8s_ingress"
  backend_service: "my-app"
  backend_namespace: "default"
  backend_port: 80
```

4. Rerun the proxy playbook to apply new routes

### Example 3: Setup Wildcard Certificates

Certificates are automatically created with Let's Encrypt. Wildcard certificates require DNS-01 challenges (already configured with Cloudflare).

Check certificate status:

```bash
ssh -p 2222 bearf@proxy-vps
sudo ls -la /var/lib/caddy/certificates/acme-v02.api.letsencrypt.org-directory/
```

## Monitoring & Troubleshooting

### View Caddy Logs

```bash
ssh -p 2222 bearf@proxy-vps

# Recent logs
sudo tail -f /var/log/caddy/access.log

# Search for specific domain
sudo grep "api.bearflinn.com" /var/log/caddy/access.log

# View errors
sudo journalctl -u caddy -n 50
```

### Test Connectivity

From VPS:

```bash
ssh -p 2222 bearf@proxy-vps

# Test K8s API server
curl -k https://10.0.0.226:6443/healthz

# Test K8s service
curl http://ingress-nginx-controller.ingress-nginx.svc.cluster.local

# Check DNS resolution
dig ingress-nginx-controller.ingress-nginx.svc.cluster.local
```

### Check Caddyfile Configuration

```bash
ssh -p 2222 bearf@proxy-vps

# Validate syntax
sudo caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile

# View current config
sudo cat /etc/caddy/Caddyfile

# Check Caddy admin API
curl http://localhost:2019/config/apps/http/servers
```

### Common Issues

#### "Connection refused" on K8s API proxy

**Problem**: Proxy can't reach K8s API server

```bash
# Verify K8s API is running
ssh 10.0.0.226 "sudo systemctl status kubelet"

# Check connectivity from VPS
ssh -p 2222 bearf@proxy-vps "nc -zv 10.0.0.226 6443"

# Verify firewall rules
ssh 10.0.0.226 "sudo ufw status"
```

#### "Bad certificate" when accessing proxy

**Problem**: SSL certificate issues

```bash
# Check certificate expiration
ssh -p 2222 bearf@proxy-vps "sudo caddy list-certs"

# Force certificate renewal
ssh -p 2222 bearf@proxy-vps "sudo systemctl restart caddy"
```

#### "Service not reachable" on K8s ingress proxy

**Problem**: Ingress controller or service not found

```bash
# Check K8s ingress controller
kubectl get svc -n ingress-nginx

# Check service endpoints
kubectl get endpoints -A

# Check DNS resolution from VPS
ssh -p 2222 bearf@proxy-vps "nslookup ingress-nginx-controller.ingress-nginx.svc.cluster.local 10.96.0.10"
```

## Configuration Files

### Proxy VPS Inventory
`ansible/inventory/proxy-vps.yml` - Host configuration and proxy routes

### Caddyfile Templates
- `ansible/roles/caddy/templates/Caddyfile.j2` - Static site template
- `ansible/roles/caddy/templates/Caddyfile-k8s.j2` - K8s proxy template (used when `enable_k8s_proxy: true`)

### Playbooks
- `ansible/playbooks/setup-proxy-vps.yml` - Initial VPS setup (Caddy, firewall, security)
- `ansible/playbooks/setup-k8s-proxy.yml` - K8s proxy configuration (routes, verification, testing)

### Roles
- `ansible/roles/caddy/` - Caddy installation and configuration
  - `tasks/main.yml` - Installation tasks
  - `defaults/main.yml` - Default variables
  - `templates/` - Caddyfile templates

## Adding New Proxy Routes

To add a new proxy route:

1. Edit `ansible/inventory/proxy-vps.yml`:

```yaml
k8s_proxy_routes:
  # ... existing routes ...
  - domain: "newapp.bearflinn.com"
    type: "k8s_ingress"
    backend_service: "newapp"
    backend_namespace: "default"
    backend_port: 8080
```

2. Rerun the playbook:

```bash
ansible-playbook -i ansible/inventory/proxy-vps.yml \
  ansible/playbooks/setup-k8s-proxy.yml --tags k8s_proxy -v
```

3. Verify in K8s that the service exists:

```bash
kubectl get svc newapp -n default
```

## Security Best Practices

1. **Use HTTPS Only**: All traffic is encrypted with Let's Encrypt
2. **Verify K8s Certificates**: Set `skip_verify: false` when using valid K8s API certificates
3. **Restrict SSH**: SSH is on port 2222 with key-based auth only
4. **Firewall Rules**: UFW blocks all inbound traffic except necessary ports
5. **Network Segmentation**: VPS and K8s cluster can be on separate networks with VPN
6. **Audit Logging**: All requests are logged in `/var/log/caddy/access.log`

## Related Documentation

- [ARCHITECTURE.md](../../ARCHITECTURE.md) - Overall lab architecture
- [README-CONTROL-PLANE.md](./README-CONTROL-PLANE.md) - K8s control plane setup
- [WORKFLOW.md](./WORKFLOW.md) - Ansible workflow documentation

## Next Steps

1. Ensure K8s cluster is running and accessible
2. Deploy nginx-ingress-controller in K8s:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml
   ```
3. Create Ingress resources for your applications
4. Test proxy routes from external network
5. Configure DNS failover or load balancing if needed

## Support

For issues or questions:
- Check logs: `ssh -p 2222 bearf@proxy-vps "sudo tail -f /var/log/caddy/access.log"`
- Validate config: `ssh -p 2222 bearf@proxy-vps "sudo caddy validate --config /etc/caddy/Caddyfile"`
- Review this guide and the ARCHITECTURE.md for context
