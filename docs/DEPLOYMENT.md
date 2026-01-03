# Deployment Guide

This guide covers deploying applications to the Kubernetes cluster, from initial setup to ongoing operations.

## Overview

The deployment architecture follows **GitOps principles**: each application repository contains its own Helm chart and CI/CD workflow. The infrastructure repository (lab-iac) manages cluster-wide components only.

```
Application Repository              Infrastructure Repository
+------------------------+         +------------------------+
|  .github/workflows/    |         |  kubernetes/           |
|    deploy.yml          |         |    github-runner/      |
|  helm/                 |         |    registry/           |
|    Chart.yaml          |         |    ingress-nginx/      |
|    values.yaml.example |         |    nfs-provisioner/    |
|    templates/          |         +------------------------+
|  Dockerfile            |
|  (application code)    |
+------------------------+
```

## Prerequisites

### Local Development
- `kubectl` configured with cluster access
- `helm` 3.x installed
- Docker for building images

### Cluster Requirements
- NGINX Ingress Controller deployed
- Container registry accessible (`10.0.0.226:32346`)
- GitHub Actions runner deployed (for CI/CD)

## Deployment Patterns

### Static Sites (landing-page, zork)

Simple deployments without databases:

**Components:**
- Deployment (nginx container serving static files)
- Service (ClusterIP)
- Ingress (NGINX Ingress Controller)

**Resources:**
- CPU: 50-100m
- Memory: 64-128Mi

**Example Helm values:**
```yaml
replicaCount: 1
image:
  repository: 10.0.0.226:32346/landing-page
  tag: latest
ingress:
  enabled: true
  host: landing.bearflinn.com
```

### Database-Backed Applications (resume-site, coaching-website, family-dashboard)

Full-stack deployments with persistent storage:

**Components:**
- App Deployment
- App Service (ClusterIP)
- Ingress
- Secret (database credentials, API keys)
- PostgreSQL StatefulSet
- Database Service (headless)
- Database PVC (persistent storage)
- Optional: Uploads PVC (for file storage)

**Database Configuration:**
- PostgreSQL 16 (pgvector extension for resume-site)
- 10-20Gi persistent storage
- Automated health checks

## Deployment Workflow

### Automatic Deployment (Recommended)

Push to production branch triggers the CI/CD pipeline:

```
1. GitHub Actions triggered on push
2. Build Docker image
3. Push to registry (10.0.0.226:32346)
4. Deploy via Helm to Kubernetes
5. Verify deployment health
```

**GitHub Actions Workflow Structure:**
```yaml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  build-and-deploy:
    runs-on: [self-hosted, kubernetes, lab]
    steps:
      - uses: actions/checkout@v4

      - name: Build and push image
        run: |
          docker build -t 10.0.0.226:32346/${{ github.repository }}:${{ github.sha }} .
          docker push 10.0.0.226:32346/${{ github.repository }}:${{ github.sha }}

      - name: Deploy with Helm
        run: |
          helm upgrade --install app-name ./helm \
            --set image.tag=${{ github.sha }} \
            --set secrets.dbPassword="${{ secrets.DB_PASSWORD }}" \
            --wait
```

### Manual Deployment

From the application repository:

```bash
# Build and push image
docker build -t 10.0.0.226:32346/app-name:v1.0.0 .
docker push 10.0.0.226:32346/app-name:v1.0.0

# Deploy with Helm
cd helm/
helm upgrade --install app-name . \
  --set image.tag=v1.0.0 \
  --set secrets.secretKey="your-secret-value" \
  --wait

# Verify deployment
kubectl get pods -l app=app-name
kubectl get ingress app-name
```

## Secrets Management

### GitHub Secrets (Most Services)

Secrets stored in GitHub repository settings, passed via `--set` flags:

```yaml
- name: Deploy to Kubernetes
  run: |
    helm upgrade --install app-name ./helm \
      --set database.password="${{ secrets.DB_PASSWORD }}" \
      --set secrets.apiKey="${{ secrets.API_KEY }}" \
      --wait
```

**Common secrets to configure:**
- `DB_PASSWORD` - PostgreSQL database password
- `SECRET_KEY` - Application secret key
- `API_KEY` - Third-party API keys

### Infisical (family-dashboard)

Family dashboard uses Infisical for centralized secret management:

```yaml
- name: Fetch secrets from Infisical
  uses: Infisical/secrets-action@v1.0.9
  with:
    method: "oidc"
    identity-id: ${{ secrets.INFISICAL_IDENTITY_ID }}
    project-slug: ${{ secrets.INFISICAL_PROJECT_SLUG }}
    env-slug: "prod"
```

### Local Development Setup

```bash
# Copy example values
cp helm/values.yaml.example helm/values.yaml

# Edit with actual secret values
vim helm/values.yaml

# Deploy locally
helm upgrade --install app-name ./helm
```

**Important:** `values.yaml` is gitignored to prevent committing secrets.

## Container Registry

### Registry Information
- **External endpoint:** `10.0.0.226:32346`
- **Internal endpoint:** `docker-registry.registry.svc.cluster.local:5000`
- **Storage:** 50Gi PVC (local-path)

### Registry Operations

```bash
# List all images
curl http://10.0.0.226:32346/v2/_catalog

# List tags for an image
curl http://10.0.0.226:32346/v2/app-name/tags/list

# Check registry status
kubectl get pods -n registry
```

### Push Images

```bash
# Tag image for registry
docker tag my-image:latest 10.0.0.226:32346/my-image:latest

# Push to registry
docker push 10.0.0.226:32346/my-image:latest
```

## Ingress Configuration

All services use NGINX Ingress Controller with NodePort access:
- **HTTP:** Port 30487
- **HTTPS:** Port 30356

### Current Ingress Endpoints

| Domain | Application |
|--------|-------------|
| landing.bearflinn.com | landing-page |
| zork.bearflinn.com | zork |
| resume.bearflinn.com | resume-site |
| coaching.bearflinn.com | coaching-website |
| family.bearflinn.com | family-dashboard |

### Example Ingress Resource

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-name
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
spec:
  ingressClassName: nginx
  rules:
  - host: app.bearflinn.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-name
            port:
              number: 80
```

## GitHub Actions Runner

Self-hosted runners execute CI/CD workflows in Kubernetes:

```yaml
jobs:
  build-and-deploy:
    runs-on: [self-hosted, kubernetes, lab]
```

**Runner Capabilities:**
- Docker-in-Docker enabled
- Helm installed
- kubectl configured with cluster access
- Access to insecure registry (10.0.0.226:32346)

### Runner RBAC Permissions
- Create/manage namespaces
- Deploy workloads (deployments, statefulsets)
- Manage services, configmaps, secrets, PVCs
- Manage ingress resources
- View pods and logs

## Storage

### Persistent Volumes

All storage uses `local-path-provisioner` (default storage class):

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
```

### Database Storage

PostgreSQL uses StatefulSet with PVC:

```yaml
volumeClaimTemplates:
- metadata:
    name: data
  spec:
    accessModes: ["ReadWriteOnce"]
    storageClassName: local-path
    resources:
      requests:
        storage: 10Gi
```

## Database Migrations

For applications with databases, migrations may need to run after deployment:

```bash
# Access the running pod
kubectl exec -it deployment/coaching-website -- /bin/sh

# Run migrations (example for Prisma)
npm run prisma:migrate

# Or for Django
python manage.py migrate
```

## Common Operations

### Check Deployment Status
```bash
kubectl get pods
kubectl get ingress
kubectl describe deployment app-name
```

### View Logs
```bash
kubectl logs deployment/app-name
kubectl logs statefulset/app-name-db
kubectl logs -f deployment/app-name  # Follow logs
```

### Update Image
```bash
helm upgrade app-name ./helm --set image.tag=new-tag --wait
```

### Rollback
```bash
helm rollback app-name
helm history app-name  # View revision history
```

### Delete Service
```bash
helm uninstall app-name

# Database PVC persists unless manually deleted
kubectl delete pvc app-name-db-data
```

### Scale Deployment
```bash
kubectl scale deployment app-name --replicas=3
```

## Best Practices

1. **Use values.yaml.example**: Document all configuration options
2. **Never commit values.yaml**: Contains secrets, keep gitignored
3. **Use semantic versioning**: Tag images with versions
4. **Set resource limits**: Prevents resource starvation
5. **Include health checks**: Enables proper rolling updates
6. **Document migrations**: Note when schema changes require manual steps
7. **Test locally first**: Use `helm template` to preview changes
8. **Use --wait flag**: Ensures deployment succeeds before workflow completes

## Troubleshooting

### Image Pull Errors
```bash
# Verify registry is accessible
curl http://10.0.0.226:32346/v2/_catalog

# Check image exists
curl http://10.0.0.226:32346/v2/app-name/tags/list

# Check pod events
kubectl describe pod <pod-name>
```

### Database Connection Issues
```bash
# Check database is running
kubectl get statefulset app-name-db
kubectl logs statefulset/app-name-db

# Verify database service
kubectl get svc app-name-db

# Test from app pod
kubectl exec -it deployment/app-name -- nc -zv app-name-db 5432
```

### Ingress Not Working
```bash
# Check ingress status
kubectl get ingress app-name
kubectl describe ingress app-name

# Verify NGINX Ingress Controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

### Secrets Not Loading
```bash
# Verify secret exists
kubectl get secret app-name-secrets

# Check secret data (base64 encoded)
kubectl get secret app-name-secrets -o yaml

# Verify pod has secret mounted
kubectl describe deployment app-name
```

## Next Steps

After mastering basic deployments:
- [ ] Add TLS/HTTPS support with cert-manager
- [ ] Implement automated database migrations
- [ ] Add monitoring with Prometheus/Grafana
- [ ] Set up backup strategy for databases
- [ ] Configure horizontal pod autoscaling
