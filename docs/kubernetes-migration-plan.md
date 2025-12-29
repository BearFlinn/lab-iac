# Kubernetes Migration Plan - Automated CI/CD Approach

## Overview

**Goal**: Migrate from Docker Compose to existing Kubernetes cluster with fully automated CI/CD deployments using Helm and GitHub Actions.

**Strategy**: Deploy infrastructure components (registry + runner) first, then create Helm charts and workflows for automated deployments. Accept some downtime during cutover.

**Timeline**: 2-3 weeks

---

## Current vs Target Architecture

**Current:**
```
Internet → Cloudflare Edge (TLS) → Cloudflare Tunnel → Caddy (localhost:80) → Docker containers
```

**Target:**
```
Internet → VPS (Caddy with TLS) → NetBird tunnel → K8s Ingress → Services
```

**Services to Migrate:**
- coaching-website: Next.js + PostgreSQL 16 - **FRESH START**
- resume-site: FastAPI + pgVector/PostgreSQL 16 - **FRESH START**
- landing-page: Nginx static site - **FRESH START**
- Monitoring: Prometheus, Grafana - **FRESH START**

**Data Migration**: None (services largely unused, accepting fresh start)

**Infrastructure Status:**
- ✅ K8s cluster running (multi-node, kubeadm)
- ✅ Ingress Controller deployed (nginx, NodePorts: 30487/30356)
- ✅ Storage Class configured (local-path, default)
- ✅ Container Registry deployed (NodePort: 32346)
- ✅ GitHub Actions Runner deployed (2 replicas, DinD working)
- ✅ TLS handled at edge (VPS Caddy)
- ✅ Helm installed (v3.19.4)
- ❌ Services (Phase 3+ - need to deploy)

---

## Phase 0: Deploy Prerequisites ✅ COMPLETED

**Goal**: Deploy Ingress Controller and Storage Class for cluster.

### Completed Steps:
1. **NGINX Ingress Controller** - Deployed via manifest
   - HTTP NodePort: 30487
   - HTTPS NodePort: 30356
   - IngressClass: `nginx`

2. **Local Path Storage Provisioner** - Deployed via manifest
   - StorageClass: `local-path` (default)
   - Dynamic volume provisioning enabled

**Files Created:**
- None (used official upstream manifests)

---

## Phase 1: Deploy Self-Hosted Container Registry ✅ COMPLETED

**Goal**: Self-hosted Docker Registry in K8s for storing application images.

### Completed Steps:
1. **Registry Manifests Created** - `k8s-manifests/registry/`
   - Namespace, PVC (50Gi), Deployment, Service (NodePort: 32346)

2. **Registry Deployed** - Running in cluster
   - Endpoint: `10.0.0.226:32346`
   - Internal DNS: `docker-registry.registry.svc.cluster.local:5000`

3. **Control Plane Configured** - Containerd configured for insecure registry
   - Script: `scripts/configure-insecure-registry.sh`
   - Ansible playbook: `ansible/playbooks/configure-registry.yml`

**Known Issues:**
- Worker nodes (msi-laptop, tower-pc) need SSH access for automated configuration
- Manual workaround: Run `configure-insecure-registry.sh` directly on workers

**Files Created:**
- `k8s-manifests/registry/` - Kubernetes manifests
- `scripts/configure-insecure-registry.sh` - Configuration script
- `ansible/playbooks/configure-registry.yml` - Ansible automation

---

## Phase 2: Deploy GitHub Actions Runner ✅ COMPLETED

**Goal**: Self-hosted GitHub Actions runners in K8s with Docker-in-Docker support.

### Completed Steps:
1. **cert-manager Installed** - Prerequisite for webhook TLS
   - Version: v1.16.2
   - Namespace: `cert-manager`

2. **Actions Runner Controller Deployed** - Via Helm
   - Chart: `actions-runner-controller/actions-runner-controller`
   - Namespace: `actions-runner-system`
   - Authentication: GitHub PAT (stored in values.yaml, git-ignored)

3. **Runner Deployment Created** - 2 replicas with DinD
   - Image: `summerwind/actions-runner-dind:latest`
   - Organization: `grizzly-endeavors`
   - Labels: `self-hosted`, `kubernetes`, `linux`, `lab`
   - Docker daemon: Configured for insecure registry

4. **Docker-in-Docker Working** - Full Docker support in runners
   - Privileged mode: Enabled
   - Insecure registry: `10.0.0.226:32346` configured via daemon.json
   - Tested: Build, push, pull all working

5. **Integration Tested** - Successful workflow run
   - Repository: `Grizzly-Endeavors/landing-page`
   - Workflow: Built and pushed nginx container
   - Image: `10.0.0.226:32346/landing-page:latest`

**Key Configuration:**
- Docker daemon config via ConfigMap (`docker-daemon-config`)
- Insecure registry and MTU settings in `/etc/docker/daemon.json`
- Resource limits: 2 CPU / 4Gi memory per runner

**Known Issues:**
- Initial attempt used wrong image (`summerwind/actions-runner` instead of `-dind`)
- Environment variables didn't configure dockerd - solved with ConfigMap volume mount

**Files Created:**
- `k8s-manifests/github-runner/` - All runner manifests
- `scripts/install-github-runner.sh` - Helm installation script
- `docs/GITHUB_RUNNER_SETUP.md` - Operations guide

**Verification:**
```bash
# Check runners in K8s
kubectl get runners -n actions-runner-system

# Check runners in GitHub
# https://github.com/organizations/grizzly-endeavors/settings/actions/runners
```

---

## Phase 3: Create Helm Charts and Workflows ✅ COMPLETED

**Goal**: Create Helm charts in each application repository and update GitHub Actions workflows for automated Kubernetes deployments.

**Architecture Decision**: Following industry best practices, Helm charts are stored IN each application repository rather than centralized in lab-iac. This follows the GitOps principle where deployment config lives with application code.

### Completed Steps:

1. **Landing Page** - Simple nginx static site
   - Created `helm/` directory with Chart.yaml, values.yaml, templates
   - Updated `.github/workflows/deploy.yml` for build → push → helm deploy
   - Ingress: `landing.grizzly-endeavors.com`

2. **Zork** - Interactive fiction games (nginx)
   - Created Helm chart following same pattern
   - Updated GitHub workflow
   - Ingress: `zork.grizzly-endeavors.com`

3. **Resume Site** - Python backend + pgvector database
   - Created Helm chart with database StatefulSet
   - Database: pgvector/pgvector:pg16 with 10Gi PVC
   - Secrets: CEREBRAS_API_KEY, GEMINI_API_KEY, DB_PASSWORD
   - Updated workflow to pass secrets via --set flags
   - Ingress: `resume.grizzly-endeavors.com`

4. **Coaching Website** - Next.js + PostgreSQL
   - Created complex Helm chart with database + uploads PVC
   - Database: postgres:16-alpine with 20Gi PVC
   - Uploads: 5Gi PVC for file storage
   - Multiple secrets: NextAuth, Discord, Stripe
   - Build-time args for Next.js public env vars
   - Ingress: `coaching.grizzly-endeavors.com`
   - Note: Database migrations must be run manually

5. **Family Dashboard** - Next.js + PostgreSQL
   - Created Helm chart with database StatefulSet
   - Database: postgres:16-alpine with 10Gi PVC
   - Secrets: AUTH_SECRET, AUTH_URL
   - Workflow includes quality checks (lint, typecheck, tests)
   - Integrates with Infisical for secret management
   - Ingress: `family.grizzly-endeavors.com`
   - Note: Database migrations must be run manually

### Files Created/Modified:

**In each application repository:**
- `helm/Chart.yaml` - Helm chart metadata
- `helm/values.yaml.example` - Template with placeholders
- `helm/.helmignore` - Excludes values.yaml (contains secrets)
- `helm/templates/deployment.yaml` - Pod deployment
- `helm/templates/service.yaml` - ClusterIP service
- `helm/templates/ingress.yaml` - NGINX ingress
- `helm/templates/secret.yaml` - Kubernetes secrets (database-backed apps)
- `helm/templates/database-*.yaml` - Database resources (database-backed apps)
- `helm/templates/*-pvc.yaml` - Persistent volume claims
- `.github/workflows/deploy.yml` - Updated for Kubernetes deployment

**In lab-iac repository:**
- `docs/DEPLOYMENT_PATTERN.md` - Comprehensive deployment documentation

### Deployment Pattern:

**Workflow:**
```
1. Push to production/main branch
2. GitHub Actions runner (running in K8s) picks up job
3. Builds Docker image
4. Pushes to registry (10.0.0.226:32346)
5. Deploys via: helm upgrade --install <service> ./helm --set secrets...
6. Waits for deployment to complete
```

**Repository Structure:**
```
project/
├── .github/workflows/deploy.yml    # Build + Deploy
├── helm/                           # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml.example
│   └── templates/
├── Dockerfile
└── (application code)
```

**Why This Pattern:**
- Self-contained services (code + deployment together)
- Independent deployments (no need to touch lab-iac)
- Industry standard (GitOps)
- CI/CD friendly (build → deploy in one workflow)

### Important Notes:

1. **Secrets Management:**
   - `values.yaml` is gitignored (contains actual secrets)
   - Secrets passed via GitHub Actions secrets + `--set` flags
   - family-dashboard uses Infisical for centralized secret management

2. **Database Migrations:**
   - Not automated yet (manual step required)
   - Run migrations manually: `kubectl exec -it deployment/app -- npm run migrate`
   - Future enhancement: Add Kubernetes Job for migrations

3. **Image Tags:**
   - Currently using `latest` tag
   - Future enhancement: Use git SHA for better rollback capability

4. **Health Checks:**
   - All deployments have liveness and readiness probes
   - Database StatefulSets have pg_isready checks
   - Init containers wait for database before starting app

### Verification:

```bash
# Check all deployments
kubectl get deployments
kubectl get statefulsets
kubectl get ingress

# Check specific service
helm list
helm status landing-page
kubectl logs deployment/landing-page
```

---

## Phase 1: Deploy Self-Hosted Container Registry (Day 1) - ORIGINAL PLAN

**Goal**: Self-hosted Docker Registry in K8s for storing application images.

### 1.1 Create Registry Manifests

**Directory**: `/home/bearf/k8s-manifests/registry/`

**`namespace.yaml`:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: registry
```

**`pvc.yaml`:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: registry-data
  namespace: registry
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
```

**`deployment.yaml`:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docker-registry
  namespace: registry
spec:
  replicas: 1
  selector:
    matchLabels:
      app: docker-registry
  template:
    metadata:
      labels:
        app: docker-registry
    spec:
      containers:
      - name: registry
        image: registry:2
        ports:
        - containerPort: 5000
        volumeMounts:
        - name: registry-data
          mountPath: /var/lib/registry
        env:
        - name: REGISTRY_STORAGE_DELETE_ENABLED
          value: "true"
      volumes:
      - name: registry-data
        persistentVolumeClaim:
          claimName: registry-data
```

**`service.yaml`:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: docker-registry
  namespace: registry
spec:
  selector:
    app: docker-registry
  ports:
  - port: 5000
    targetPort: 5000
  type: NodePort
```

### 1.2 Deploy Registry

```bash
kubectl apply -f /home/bearf/k8s-manifests/registry/
kubectl wait --for=condition=ready pod -l app=docker-registry -n registry --timeout=120s
```

### 1.3 Test Registry Access

```bash
# Get NodePort
REGISTRY_PORT=$(kubectl get svc -n registry docker-registry -o jsonpath='{.spec.ports[0].nodePort}')
echo "Registry available at: <node-ip>:$REGISTRY_PORT"

# Test push (from any node or machine that can reach cluster)
docker pull hello-world
docker tag hello-world <node-ip>:$REGISTRY_PORT/hello-world
docker push <node-ip>:$REGISTRY_PORT/hello-world
```

**Registry URL for K8s**: `docker-registry.registry.svc.cluster.local:5000`
**Registry URL for external** (GitHub Actions): `<node-ip>:<nodeport>`

---

## Phase 2: Deploy GitHub Actions Runner (Day 1-2)

**Goal**: Deploy Actions runner in K8s to enable automated deployments.

### 2.1 Install actions-runner-controller

**Install cert-manager** (dependency):
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
kubectl wait --for=condition=ready pod -n cert-manager --all --timeout=180s
```

**Install actions-runner-controller**:
```bash
kubectl apply -f https://github.com/actions/actions-runner-controller/releases/latest/download/actions-runner-controller.yaml
```

### 2.2 Create GitHub PAT Secret

**Create PAT** with permissions:
- `repo` (full control)
- `admin:org` → `manage_runners:org`

```bash
kubectl create secret generic controller-manager \
    -n actions-runner-system \
    --from-literal=github_token=YOUR_PAT_TOKEN
```

### 2.3 Deploy Runner

**File**: `/home/bearf/k8s-manifests/github-runner/runner-deployment.yaml`

```yaml
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: grizzly-endeavors-runner
  namespace: actions-runner-system
spec:
  replicas: 2
  template:
    spec:
      organization: grizzly-endeavors
      labels:
        - kubernetes
        - self-hosted
        - linux
      dockerdWithinRunnerContainer: true  # Enable Docker builds
```

**Deploy**:
```bash
kubectl apply -f /home/bearf/k8s-manifests/github-runner/runner-deployment.yaml
kubectl get runners -n actions-runner-system
```

### 2.4 Verify Runners

1. Go to GitHub organization settings → Actions → Runners
2. Should see 2 runners labeled `kubernetes` as "Idle"

### 2.5 Configure Image Push to Registry

**Create Kubernetes secret for insecure registry** (homelab, no TLS):

```bash
# On each node, configure insecure registry
sudo nano /etc/containerd/config.toml
# Add under [plugins."io.containerd.grpc.v1.cri".registry.configs]
#   [plugins."io.containerd.grpc.v1.cri".registry.configs."<node-ip>:<nodeport>"]
#     [plugins."io.containerd.grpc.v1.cri".registry.configs."<node-ip>:<nodeport>".tls]
#       insecure_skip_verify = true

sudo systemctl restart containerd
```

---

## Phase 3: Create Helm Charts (Day 3-4)

**Goal**: Create reusable Helm charts for each service.

### 3.1 Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

### 3.2 Create Helm Chart Structure

**For each service**: coaching-website, resume-site, landing-page

```bash
cd /home/bearf/k8s-manifests
helm create coaching-website
helm create resume-site
helm create landing-page
```

This creates standard chart structure:
```
coaching-website/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   └── _helpers.tpl
```

### 3.3 Helm Chart - Coaching Website

**Reference**: `/home/bearf/actions-runner/_work/coaching-website/coaching-website/docker-compose.yml`

**`coaching-website/values.yaml`:**
```yaml
replicaCount: 2

image:
  repository: <node-ip>:<nodeport>/coaching-website
  tag: latest
  pullPolicy: Always

service:
  type: ClusterIP
  port: 3000

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: coaching.yourdomain.com
      paths:
        - path: /
          pathType: Prefix

env:
  - name: NODE_ENV
    value: production
  - name: DATABASE_URL
    value: postgresql://coaching_user:CHANGE_ME@postgres:5432/coaching
  - name: NEXTAUTH_URL
    value: https://coaching.yourdomain.com
  - name: NEXTAUTH_SECRET
    valueFrom:
      secretKeyRef:
        name: coaching-secrets
        key: nextauth-secret

postgresql:
  enabled: true
  auth:
    username: coaching_user
    password: CHANGE_ME
    database: coaching
  primary:
    persistence:
      enabled: true
      size: 10Gi
```

**`coaching-website/templates/deployment.yaml`:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "coaching-website.fullname" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "coaching-website.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "coaching-website.selectorLabels" . | nindent 8 }}
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - containerPort: {{ .Values.service.port }}
        env:
        {{- toYaml .Values.env | nindent 8 }}
```

**`coaching-website/templates/postgres-statefulset.yaml`** (create new):
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:16-alpine
        env:
        - name: POSTGRES_USER
          value: {{ .Values.postgresql.auth.username }}
        - name: POSTGRES_PASSWORD
          value: {{ .Values.postgresql.auth.password }}
        - name: POSTGRES_DB
          value: {{ .Values.postgresql.auth.database }}
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
          subPath: pgdata
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: {{ .Values.postgresql.primary.persistence.size }}
```

### 3.4 Helm Chart - Resume Site

**Reference**: `/home/bearf/actions-runner/_work/resume-site/resume-site/docker-compose.yml`

**Key differences**:
- Use `pgvector/pgvector:pg16` image for PostgreSQL
- Port 8000 (FastAPI/Uvicorn)
- Environment variables: `DATABASE_URL`, `CEREBRAS_API_KEY`, `GEMINI_API_KEY`

**`resume-site/values.yaml`:**
```yaml
replicaCount: 2

image:
  repository: <node-ip>:<nodeport>/resume-site
  tag: latest

service:
  port: 8000

ingress:
  enabled: true
  hosts:
    - host: resume.yourdomain.com
      paths:
        - path: /
          pathType: Prefix

env:
  - name: DATABASE_URL
    value: postgresql://resume_user:CHANGE_ME@postgres:5432/resume
  - name: CEREBRAS_API_KEY
    valueFrom:
      secretKeyRef:
        name: resume-secrets
        key: cerebras-api-key
  - name: GEMINI_API_KEY
    valueFrom:
      secretKeyRef:
        name: resume-secrets
        key: gemini-api-key

postgresql:
  enabled: true
  image: pgvector/pgvector:pg16
  auth:
    username: resume_user
    password: CHANGE_ME
    database: resume
```

### 3.5 Helm Chart - Landing Page

**Reference**: `/home/bearf/actions-runner/_work/landing-page/landing-page/docker-compose.yml`

**Simple nginx static site**:

**`landing-page/values.yaml`:**
```yaml
replicaCount: 2

image:
  repository: <node-ip>:<nodeport>/landing-page
  tag: latest

service:
  port: 80

ingress:
  enabled: true
  hosts:
    - host: bearflinn.com
      paths:
        - path: /
          pathType: Prefix
```

---

## Phase 4: Create GitHub Actions Workflows (Day 4-5)

**Goal**: Automate build, push, and deploy for each service.

### 4.1 Workflow Template

**Pattern for each repository**:

1. Build Docker image
2. Push to self-hosted registry
3. Deploy to K8s using Helm

### 4.2 Coaching Website Workflow

**File**: `.github/workflows/deploy-k8s.yml` (in coaching-website repo)

```yaml
name: Build and Deploy to Kubernetes

on:
  push:
    branches: [ main ]
  workflow_dispatch:

env:
  REGISTRY: <node-ip>:<nodeport>
  IMAGE_NAME: coaching-website

jobs:
  build-and-deploy:
    runs-on: [self-hosted, kubernetes]
    steps:
      - uses: actions/checkout@v4

      - name: Build Docker image
        run: |
          docker build -t $REGISTRY/$IMAGE_NAME:${{ github.sha }} .
          docker tag $REGISTRY/$IMAGE_NAME:${{ github.sha }} $REGISTRY/$IMAGE_NAME:latest

      - name: Push to registry
        run: |
          docker push $REGISTRY/$IMAGE_NAME:${{ github.sha }}
          docker push $REGISTRY/$IMAGE_NAME:latest

      - name: Create secrets
        run: |
          kubectl create namespace coaching-website --dry-run=client -o yaml | kubectl apply -f -
          kubectl create secret generic coaching-secrets \
            --from-literal=nextauth-secret=${{ secrets.NEXTAUTH_SECRET }} \
            --from-literal=discord-client-id=${{ secrets.DISCORD_CLIENT_ID }} \
            --from-literal=discord-client-secret=${{ secrets.DISCORD_CLIENT_SECRET }} \
            --from-literal=stripe-secret-key=${{ secrets.STRIPE_SECRET_KEY }} \
            -n coaching-website \
            --dry-run=client -o yaml | kubectl apply -f -

      - name: Deploy with Helm
        run: |
          helm upgrade --install coaching-website ./k8s/coaching-website \
            --namespace coaching-website \
            --create-namespace \
            --set image.tag=latest \
            --wait

      - name: Verify deployment
        run: |
          kubectl rollout status deployment/coaching-website -n coaching-website
          kubectl get pods -n coaching-website
```

### 4.3 Resume Site Workflow

**File**: `.github/workflows/deploy-k8s.yml` (in resume-site repo)

**Similar structure, key differences**:
- IMAGE_NAME: resume-site
- Secrets: CEREBRAS_API_KEY, GEMINI_API_KEY
- Namespace: resume-site

### 4.4 Landing Page Workflow

**Simplest workflow** (static site, no secrets):

```yaml
name: Deploy Landing Page

on:
  push:
    branches: [ main ]

env:
  REGISTRY: <node-ip>:<nodeport>
  IMAGE_NAME: landing-page

jobs:
  deploy:
    runs-on: [self-hosted, kubernetes]
    steps:
      - uses: actions/checkout@v4

      - name: Build and push
        run: |
          docker build -t $REGISTRY/$IMAGE_NAME:latest .
          docker push $REGISTRY/$IMAGE_NAME:latest

      - name: Deploy
        run: |
          helm upgrade --install landing-page ./k8s/landing-page \
            --namespace landing-page \
            --create-namespace \
            --wait
```

### 4.5 Add Helm Charts to Repositories

**For each repository**, create `/k8s/<service-name>/` directory and copy Helm chart files:

```bash
# In coaching-website repo
mkdir -p k8s
cp -r /home/bearf/k8s-manifests/coaching-website k8s/
git add k8s/
git commit -m "Add Helm chart for Kubernetes deployment"
git push
```

**Repeat for resume-site and landing-page**

### 4.6 Add GitHub Secrets

**For each repository**, add secrets via GitHub UI:

**coaching-website**:
- NEXTAUTH_SECRET
- DISCORD_CLIENT_ID
- DISCORD_CLIENT_SECRET
- STRIPE_SECRET_KEY

**resume-site**:
- CEREBRAS_API_KEY
- GEMINI_API_KEY

---

## Phase 5: Deploy Monitoring Stack (Day 6)

**Goal**: Deploy Prometheus, Grafana, and alerting to K8s.

### 5.1 Install kube-prometheus-stack with Helm

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=14d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
  --set grafana.adminPassword=CHANGE_ME \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size=10Gi
```

**Includes**:
- Prometheus Operator
- Prometheus (14-day retention)
- Grafana (with default dashboards)
- Alertmanager
- Node Exporter (all nodes)
- kube-state-metrics

### 5.2 Create Grafana Ingress

**File**: `/home/bearf/k8s-manifests/monitoring/grafana-ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
spec:
  ingressClassName: nginx
  rules:
  - host: grafana.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus-grafana
            port:
              number: 80
```

```bash
kubectl apply -f /home/bearf/k8s-manifests/monitoring/grafana-ingress.yaml
```

### 5.3 Migrate Alert Rules

**Reference**: `/home/bearf/monitoring/prometheus/alerts.yml`

**Convert to PrometheusRule CRD** (`/home/bearf/k8s-manifests/monitoring/alert-rules.yaml`):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: homelab-alerts
  namespace: monitoring
spec:
  groups:
  - name: system_alerts
    interval: 30s
    rules:
    - alert: HighCPUUsage
      expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High CPU usage on {{ $labels.instance }}"

    - alert: HighMemoryUsage
      expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "High memory usage on {{ $labels.instance }}"

    # Add remaining 14 alert rules from existing alerts.yml
```

```bash
kubectl apply -f /home/bearf/k8s-manifests/monitoring/alert-rules.yaml
```

---

## Phase 6: VPS Caddy Configuration (Day 7)

**Goal**: Configure VPS to route traffic through NetBird to K8s cluster.

### 6.1 Get Ingress Controller NodePort

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
# Note the NodePort (e.g., 30080 for HTTP, 30443 for HTTPS)
```

### 6.2 Verify NetBird Tunnel

**On VPS**:
```bash
ping <netbird-ip-of-control-plane>
# Should work if NetBird tunnel is active
```

**NetBird IP example**:
- VPS: 100.64.0.1
- K8s control plane: 100.64.0.2

### 6.3 Update VPS Caddyfile

**File**: `/etc/caddy/Caddyfile` (on VPS)

```
{
    email your-email@example.com
}

# Production routes (after DNS cutover)
coaching.yourdomain.com {
    reverse_proxy http://100.64.0.2:30080
    header X-Served-By "VPS-Edge"
}

resume.yourdomain.com {
    reverse_proxy http://100.64.0.2:30080
}

bearflinn.com {
    reverse_proxy http://100.64.0.2:30080
}

grafana.yourdomain.com {
    reverse_proxy http://100.64.0.2:30080
}

# Health check
health.yourdomain.com {
    respond "VPS Edge OK" 200
}

# Catch-all for undefined subdomains
*.yourdomain.com {
    respond "Not Found" 404
}
```

**Reload Caddy**:
```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

---

## Phase 7: Deploy Services & DNS Cutover (Day 8-10)

**Goal**: Deploy all services via CI/CD and update DNS.

### 7.1 Trigger Deployments

**For each repository** (coaching-website, resume-site, landing-page):

1. Push Helm charts to repository
2. Push GitHub Actions workflow
3. Trigger workflow (via git push or manual dispatch)
4. Monitor deployment:

```bash
# Watch coaching-website deployment
kubectl get pods -n coaching-website -w

# Check logs
kubectl logs -n coaching-website -l app=coaching-website --tail=50 -f

# Verify service
kubectl get svc,ingress -n coaching-website
```

### 7.2 Test Through VPS (Before DNS Change)

**Add to local `/etc/hosts` for testing**:
```
<vps-ip> coaching.yourdomain.com
<vps-ip> resume.yourdomain.com
<vps-ip> bearflinn.com
<vps-ip> grafana.yourdomain.com
```

**Test each service**:
```bash
curl https://coaching.yourdomain.com
curl https://resume.yourdomain.com
curl https://bearflinn.com
curl https://grafana.yourdomain.com
```

**Verify**:
- TLS certificates issued by Caddy on VPS
- Applications responding correctly
- Databases connected
- Authentication working

### 7.3 DNS Cutover

**Update DNS A records** to point to VPS IP:
- `coaching.yourdomain.com` → VPS IP
- `resume.yourdomain.com` → VPS IP
- `bearflinn.com` → VPS IP
- `grafana.yourdomain.com` → VPS IP

**DNS propagation**: Wait 5-60 minutes (depends on TTL)

### 7.4 Monitor Post-Cutover

```bash
# Monitor all namespaces
watch kubectl get pods --all-namespaces

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit http://localhost:9090/targets

# Check Grafana dashboards
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Visit http://localhost:3000
```

### 7.5 Decommission Old Services

**After 24 hours of stable operation**:

1. Stop Docker containers:
```bash
ssh user@10.0.0.187
cd /home/bearf/actions-runner/_work/coaching-website/coaching-website
docker-compose down

cd /home/bearf/actions-runner/_work/resume-site/resume-site
docker-compose down

cd /home/bearf/monitoring
docker-compose down
```

2. Stop Cloudflare Tunnel:
```bash
sudo systemctl stop cloudflared
sudo systemctl disable cloudflared
```

3. Stop host Caddy:
```bash
sudo systemctl stop caddy
sudo systemctl disable caddy
```

4. Archive Docker volumes (optional backup):
```bash
sudo tar -czf /backup/docker-volumes-archive-$(date +%Y%m%d).tar.gz /var/lib/docker/volumes/
```

5. Stop host-based GitHub runner:
```bash
sudo systemctl stop actions.runner.grizzly-endeavors.deb-webserver.service
sudo systemctl disable actions.runner.grizzly-endeavors.deb-webserver.service
```

---

## Rollback Procedures

### If Service Fails After Deployment

**Option 1: Rollback with Helm**
```bash
helm rollback coaching-website -n coaching-website
```

**Option 2: Redeploy Previous Version**
```bash
helm upgrade --install coaching-website ./k8s/coaching-website \
  --namespace coaching-website \
  --set image.tag=<previous-sha>
```

### If Complete K8s Failure

1. **Restore VPS Caddyfile** to route to old server:
```
coaching.yourdomain.com {
    reverse_proxy http://10.0.0.187:3000
}
# ... etc
```

2. **Restart Docker services**:
```bash
cd /home/bearf/actions-runner/_work/coaching-website/coaching-website
docker-compose up -d
```

3. **Restart Cloudflare Tunnel** (if still configured):
```bash
sudo systemctl start cloudflared
```

**Recovery time**: < 10 minutes

---

## Success Criteria

Migration complete when:
- ✅ Self-hosted container registry running
- ✅ GitHub Actions runner deployed in K8s
- ✅ All 3 services deployed via Helm/GitHub Actions
- ✅ Monitoring stack running with Prometheus + Grafana
- ✅ VPS Caddy routing traffic through NetBird to K8s
- ✅ DNS cutover complete
- ✅ TLS certificates working (issued by VPS Caddy)
- ✅ All services accessible via production domains
- ✅ 24+ hours stable operation
- ✅ Old Docker services decommissioned

---

## Timeline Summary

| Day | Phase | Activities |
|-----|-------|-----------|
| 1 | Registry | Deploy self-hosted Docker registry |
| 1-2 | Runner | Deploy GitHub Actions runner to K8s |
| 3-4 | Helm Charts | Create charts for all 3 services |
| 4-5 | Workflows | Create GitHub Actions workflows |
| 6 | Monitoring | Deploy kube-prometheus-stack |
| 7 | VPS | Configure Caddy routing via NetBird |
| 8-10 | Deploy | Trigger CI/CD, test, DNS cutover |

**Total: 10-14 days** (depending on testing thoroughness)

---

## Critical Files Reference

### Files to Read/Reference

1. **Docker Compose Configs** (for converting to Helm values):
   - `/home/bearf/actions-runner/_work/coaching-website/coaching-website/docker-compose.yml`
   - `/home/bearf/actions-runner/_work/resume-site/resume-site/docker-compose.yml`
   - `/home/bearf/actions-runner/_work/landing-page/landing-page/docker-compose.yml`

2. **Monitoring Configuration**:
   - `/home/bearf/monitoring/prometheus/alerts.yml` (convert to PrometheusRule)
   - `/home/bearf/monitoring/docker-compose.yml` (retention, volumes)

3. **Current Routing**:
   - `/home/bearf/ansible/vars/caddy-routes.yml` (for VPS Caddyfile)

### Files to Create

1. **K8s Manifests** (`/home/bearf/k8s-manifests/`):
   - `registry/` - Docker registry deployment
   - `github-runner/` - Runner deployment
   - `monitoring/` - Grafana ingress, alert rules

2. **Helm Charts** (`/home/bearf/k8s-manifests/` and in each git repo):
   - `coaching-website/` - Chart for coaching site
   - `resume-site/` - Chart for resume site
   - `landing-page/` - Chart for landing page

3. **GitHub Actions Workflows** (in each repository):
   - `.github/workflows/deploy-k8s.yml`

4. **VPS Configuration**:
   - `/etc/caddy/Caddyfile` (on VPS)

5. **Documentation Updates**:
   - `/home/bearf/docs/kubernetes-cluster.md` - New doc for K8s operations
   - `/home/bearf/docs/ci-cd-workflows.md` - GitHub Actions + Helm deployment guide
   - `/home/bearf/CLAUDE.md` - Update to reflect new architecture

---

## Cost Analysis

**New Recurring Costs**:
- VPS: ~$5-6/month

**No Change**:
- K8s hardware: Already provisioned
- NetBird: Free tier (up to 5 peers)

**Total new monthly cost**: ~$5-6/month

---

## Key Benefits

1. **Automated Deployments**: Push to git → auto-deploy to K8s
2. **Scalability**: Replicas, horizontal pod autoscaling ready
3. **Resilience**: Multi-node cluster, pod restarts
4. **Monitoring**: Prometheus metrics, Grafana dashboards, alerting
5. **Learning**: Real-world K8s + Helm + GitOps experience
6. **Fresh Start**: No legacy Docker Compose baggage