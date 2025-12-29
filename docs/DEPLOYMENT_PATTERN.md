# Kubernetes Deployment Pattern

## Overview

This document describes the deployment pattern used for all services in the Kubernetes cluster. Following industry best practices, each application repository contains its own Helm chart and deployment workflow.

## Architecture

### Repository Structure

**Application Repositories** (landing-page, zork, resume-site, coaching-website, family-dashboard):
```
project/
├── .github/workflows/
│   └── deploy.yml          # CI/CD pipeline: build → push → deploy
├── helm/                    # Helm chart for this service
│   ├── Chart.yaml
│   ├── values.yaml.example  # Template with placeholders
│   ├── .helmignore         # Excludes values.yaml (contains secrets)
│   └── templates/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── secret.yaml      # (if needed)
│       ├── database-*.yaml  # (if database required)
│       └── *-pvc.yaml       # (if persistent storage required)
├── Dockerfile
└── (application code)
```

**Infrastructure Repository** (lab-iac):
```
lab-iac/
├── ansible/                 # Configuration management
├── k8s-manifests/          # Cluster-wide infrastructure only
│   ├── registry/           # Container registry
│   └── github-runner/      # CI/CD runners
├── scripts/                 # Automation scripts
└── docs/                    # Documentation
```

### Why This Pattern?

This follows the **GitOps** principle where application code and deployment configuration live together:

1. **Self-contained services**: Each app owns its deployment config
2. **Independent deployment**: Deploy any service without touching infrastructure repo
3. **Industry standard**: Used by companies like Google, Netflix, Airbnb
4. **CI/CD friendly**: Build → Test → Deploy in one workflow
5. **Version control**: Deployment config versioned with code it deploys

## Deployment Workflow

### Automatic Deployment (Recommended)

Push to production branch triggers:
```
1. Build Docker image
2. Push to registry (10.0.0.226:32346)
3. Deploy via Helm to Kubernetes
```

### Manual Deployment

From the application repository:
```bash
# Build and push image
docker build -t 10.0.0.226:32346/app-name:tag .
docker push 10.0.0.226:32346/app-name:tag

# Deploy with Helm
cd helm/
helm upgrade --install app-name . \
  --set image.tag=tag \
  --set secrets.secretKey="value" \
  --wait
```

## Service Types

### Static Sites (landing-page, zork)

**Components:**
- Deployment (nginx container)
- Service (ClusterIP)
- Ingress (NGINX Ingress Controller)

**Resources:**
- CPU: 50-100m
- Memory: 64-128Mi

**No database or persistent storage needed**

### Database-Backed Apps (resume-site, coaching-website, family-dashboard)

**Components:**
- App Deployment
- App Service
- Ingress
- Secret (for sensitive environment variables)
- Database StatefulSet
- Database Service (headless)
- Database PVC (persistent storage)
- Optional: Uploads PVC (for file storage)

**Database:**
- PostgreSQL 16 (pgvector for resume-site)
- 10-20Gi persistent storage
- Automated health checks

**Important:** Database migrations must be run manually after deployment if schema changed

## Secrets Management

### GitHub Secrets (Most Services)

Secrets are stored in GitHub repository settings and passed via `--set` flags:

```yaml
- name: Deploy to Kubernetes with Helm
  run: |
    helm upgrade --install app-name ./helm \
      --set database.password="${{ secrets.DB_PASSWORD }}" \
      --set secrets.apiKey="${{ secrets.API_KEY }}" \
      --wait
```

### Infisical (family-dashboard)

Family dashboard uses Infisical for secret management:

```yaml
- name: Fetch secrets from Infisical
  uses: Infisical/secrets-action@v1.0.9
  with:
    method: "oidc"
    identity-id: ${{ secrets.INFISICAL_IDENTITY_ID }}
    # ... exports secrets as env vars
```

### Local Development

1. Copy `helm/values.yaml.example` to `helm/values.yaml`
2. Fill in actual secret values
3. Deploy: `helm upgrade --install app-name ./helm`

**Important:** `values.yaml` is gitignored to prevent committing secrets

## Ingress Configuration

All services use NGINX Ingress Controller:

**Current Ingress Endpoints:**
- landing.grizzly-endeavors.com → landing-page
- zork.grizzly-endeavors.com → zork
- resume.grizzly-endeavors.com → resume-site
- coaching.grizzly-endeavors.com → coaching-website
- family.grizzly-endeavors.com → family-dashboard

**Access via NodePorts:**
- HTTP: Port 30487
- HTTPS: Port 30356

**Example from VPS:**
```bash
# Add to /etc/hosts on proxy-vps
10.0.0.226 landing.grizzly-endeavors.com

# Test
curl http://landing.grizzly-endeavors.com:30487
```

## Storage

All persistent storage uses `local-path-provisioner` (default storage class).

**Database Storage:**
- Creates PersistentVolumeClaim
- Mounted to StatefulSet
- Survives pod restarts

**Uploads/Files:**
- Separate PVC for file uploads (coaching-website)
- Mounted to `/app/uploads`

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
```

### Update Image
```bash
helm upgrade app-name ./helm --set image.tag=new-tag
```

### Rollback
```bash
helm rollback app-name
```

### Delete Service
```bash
helm uninstall app-name
# Database PVC will persist unless manually deleted
kubectl delete pvc app-name-db-data
```

## Database Migrations

For services with databases (resume-site, coaching-website, family-dashboard):

**Manual Migration:**
```bash
# Get a shell in the running pod
kubectl exec -it deployment/coaching-website -- /bin/sh

# Run migrations (example for Prisma)
npm run prisma:migrate
```

**Future Enhancement:** Could add a Kubernetes Job to run migrations automatically

## GitHub Actions Runners

Workflows run on self-hosted runners in the Kubernetes cluster:

```yaml
jobs:
  build-and-deploy:
    runs-on: [self-hosted, kubernetes, lab]
```

**Runner Features:**
- Docker-in-Docker enabled
- Helm installed
- kubectl configured
- Access to insecure registry

## Troubleshooting

### Image Pull Errors
```bash
# Verify registry is accessible
curl http://10.0.0.226:32346/v2/_catalog

# Check image exists
curl http://10.0.0.226:32346/v2/app-name/tags/list
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

## Migration from Docker Compose

Services were previously deployed with Docker Compose on deb-web. Key changes:

**Old Pattern:**
```yaml
# docker-compose.yml
services:
  app:
    build: .
    ports:
      - "3000:80"
```

**New Pattern:**
```yaml
# GitHub Actions builds image
# Helm deploys to Kubernetes with Ingress
```

**Benefits:**
- No port conflicts (Ingress handles routing)
- Scalable (can run multiple replicas)
- Self-healing (Kubernetes restarts failed pods)
- Better resource management
- Proper health checks

## Best Practices

1. **Always use values.yaml.example**: Document all configuration options
2. **Never commit values.yaml**: Contains secrets, gitignored
3. **Use semantic versioning**: Tag images with versions
4. **Set resource limits**: Prevents resource starvation
5. **Include health checks**: Enables proper rolling updates
6. **Document migrations**: Note when schema changes require manual steps
7. **Test locally first**: Use `helm template` to preview changes
8. **Use --wait flag**: Ensures deployment succeeds before workflow completes

## Next Steps

- [ ] Add TLS/HTTPS support with cert-manager
- [ ] Implement automated database migrations
- [ ] Add monitoring with Prometheus/Grafana
- [ ] Set up backup strategy for databases
- [ ] Configure horizontal pod autoscaling
- [ ] Add development/staging environments
