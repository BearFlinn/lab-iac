# NGINX Ingress Controller

## Overview

NGINX Ingress Controller for Kubernetes cluster, configured for bare-metal deployment.

## Configuration

- **Namespace**: `ingress-nginx`
- **HTTP NodePort**: `30487`
- **HTTPS NodePort**: `30356`
- **IngressClass**: `nginx` (default)
- **Version**: v1.11.3

## Deployment

The ingress controller is deployed using the official NGINX ingress controller manifest for bare-metal Kubernetes.

### Install

```bash
./scripts/install-ingress-nginx.sh
```

### Manual Installation

```bash
# Apply base manifest
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/baremetal/deploy.yaml

# Patch service to use specific NodePorts
kubectl patch service ingress-nginx-controller \
    -n ingress-nginx \
    --type='json' \
    -p='[
        {"op": "replace", "path": "/spec/ports/0/nodePort", "value": 30487},
        {"op": "replace", "path": "/spec/ports/1/nodePort", "value": 30356}
    ]'
```

## Usage

### Create an Ingress Resource

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  namespace: default
spec:
  ingressClassName: nginx
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: example-service
            port:
              number: 80
```

### Access Services

Services are accessible through any cluster node at the configured NodePorts:
- HTTP: `http://<node-ip>:30487`
- HTTPS: `https://<node-ip>:30356`

## Integration with VPS

The VPS Caddy server routes traffic through NetBird tunnel to the ingress controller:

```
Internet → VPS (Caddy with TLS) → NetBird tunnel → K8s Ingress (NodePort 30487/30356) → Services
```

## Verification

```bash
# Check ingress controller status
kubectl get all -n ingress-nginx

# Check ingress class
kubectl get ingressclass

# Check service and NodePorts
kubectl get svc -n ingress-nginx ingress-nginx-controller

# View logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

## Troubleshooting

### Ingress not routing traffic

1. Check ingress controller logs:
   ```bash
   kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
   ```

2. Verify ingress resource is created:
   ```bash
   kubectl get ingress -A
   ```

3. Check service endpoints:
   ```bash
   kubectl describe ingress <ingress-name> -n <namespace>
   ```

### NodePort not accessible

1. Verify NodePort is allocated:
   ```bash
   kubectl get svc -n ingress-nginx ingress-nginx-controller
   ```

2. Check firewall rules on nodes

3. Verify NetBird tunnel connectivity (if accessing through VPS)
