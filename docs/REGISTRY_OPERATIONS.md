# Container Registry Operations

## Registry Information

- **Endpoint (external)**: `10.0.0.226:32346`
- **Endpoint (internal)**: `docker-registry.registry.svc.cluster.local:5000`
- **Namespace**: `registry`
- **Storage**: 50Gi PVC (local-path)

## Common Operations

### Check Registry Status

```bash
kubectl get pods -n registry
kubectl get svc -n registry
```

### View Registry Catalog (list all images)

```bash
# From within cluster
kubectl exec -n registry deployment/docker-registry -- wget -qO- http://localhost:5000/v2/_catalog

# From external (requires network access to NodePort)
curl http://10.0.0.226:32346/v2/_catalog
```

### List Tags for an Image

```bash
# Replace IMAGE_NAME with actual image name
kubectl exec -n registry deployment/docker-registry -- wget -qO- http://localhost:5000/v2/IMAGE_NAME/tags/list
```

### Push an Image (from nodes configured for insecure registry)

```bash
# Tag the image
docker tag my-image:latest 10.0.0.226:32346/my-image:latest

# Push to registry
docker push 10.0.0.226:32346/my-image:latest
```

### Pull an Image in Kubernetes

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: 10.0.0.226:32346/my-image:latest
```

## Node Configuration

### Configure Worker Nodes for Insecure Registry

**Automated (requires SSH access):**
```bash
cd ~/Projects/lab-iac/ansible
ansible-playbook -i inventory/all-nodes.yml playbooks/configure-registry.yml
```

**Manual (run on each worker node):**
```bash
sudo /path/to/configure-insecure-registry.sh 10.0.0.226:32346
```

The script will:
- Configure containerd to trust the insecure registry
- Fix CNI binary path if needed
- Backup config and auto-rollback on failure

### Verify Node Configuration

```bash
# On the node
sudo grep -A2 "10.0.0.226:32346" /etc/containerd/config.toml
```

## Troubleshooting

### Pod Can't Pull from Registry

1. **Check registry is running:**
   ```bash
   kubectl get pods -n registry
   ```

2. **Verify node is configured:**
   ```bash
   ssh node "sudo grep '10.0.0.226:32346' /etc/containerd/config.toml"
   ```

3. **Check containerd logs on the node:**
   ```bash
   ssh node "sudo journalctl -u containerd -n 50"
   ```

### Registry Storage Full

```bash
# Check PVC usage
kubectl exec -n registry deployment/docker-registry -- df -h /var/lib/registry

# If needed, increase PVC size
kubectl edit pvc -n registry registry-data
```

### Delete Registry (WARNING: Destroys all images)

```bash
kubectl delete -f ~/Projects/lab-iac/k8s-manifests/registry/
```

## GitHub Actions Integration

Images will be automatically pushed from GitHub Actions workflows (Phase 4).

Example workflow snippet:
```yaml
env:
  REGISTRY: 10.0.0.226:32346

steps:
  - name: Build and push
    run: |
      docker build -t $REGISTRY/my-app:${{ github.sha }} .
      docker push $REGISTRY/my-app:${{ github.sha }}
```
