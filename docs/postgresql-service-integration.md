# PostgreSQL Service Integration Guide

This guide covers integrating your Helm-deployed applications with the PostgreSQL database server running on tower-pc, using GitHub Actions secrets and Infisical for secret management.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Helm Chart Integration](#helm-chart-integration)
4. [Secret Management](#secret-management)
5. [GitHub Actions Deployment](#github-actions-deployment)
6. [Example Applications](#example-applications)
7. [Migration from Existing Databases](#migration-from-existing-databases)
8. [Troubleshooting](#troubleshooting)
9. [Security Best Practices](#security-best-practices)

---

## Overview

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ GitHub Actions CI/CD                                            │
│                                                                  │
│  ┌──────────────┐         ┌────────────────┐                   │
│  │ GitHub       │────────▶│ Infisical      │                   │
│  │ Secrets      │         │ Secrets        │                   │
│  └──────────────┘         └────────────────┘                   │
│         │                          │                             │
│         │    Helm Deploy           │                             │
│         ▼                          ▼                             │
└─────────┼──────────────────────────┼─────────────────────────────┘
          │                          │
          │                          │
┌─────────┼──────────────────────────┼─────────────────────────────┐
│         │  Kubernetes Cluster      │                             │
│         │                          │                             │
│         ▼                          ▼                             │
│  ┌──────────────┐         ┌──────────────────────────┐         │
│  │ Application  │────────▶│ Service: postgresql      │         │
│  │ Pod (Helm)   │         │ (database namespace)     │         │
│  └──────────────┘         └──────────────────────────┘         │
│                                      │                           │
└──────────────────────────────────────┼───────────────────────────┘
                                       │
                                       │ TLS Connection
                                       │ (port 5432)
                                       ▼
                            ┌─────────────────────┐
                            │ tower-pc            │
                            │ 10.0.0.249:5432     │
                            │                     │
                            │ PostgreSQL 16.11    │
                            │ (Docker Container)  │
                            └─────────────────────┘
```

### Available Databases

| Database Name      | Owner             | Purpose                    |
|--------------------|-------------------|----------------------------|
| `coaching`         | `coaching_user`   | Coaching website database  |
| `resume`           | `resume_user`     | Resume site database       |
| `family_dashboard` | `dashboard_user`  | Family dashboard database  |

### Connection Details

- **Hostname**: `postgresql.database.svc.cluster.local`
- **Port**: `5432`
- **SSL Mode**: `require` (TLS enabled)
- **Network**: Accessible from all Kubernetes pods

---

## Prerequisites

Before integrating your application:

1. **Kubernetes Cluster**: Applications deployed via Helm
2. **Database Namespace**: The `database` namespace exists
3. **TLS Certificate**: The `postgresql-tls-ca` secret exists in the `database` namespace
4. **Database Credentials**: Stored in GitHub Actions secrets or Infisical
5. **Helm Chart**: Your application uses Helm for deployment

### Verify Prerequisites

```bash
# Check namespace
kubectl get namespace database

# Check service and endpoints
kubectl get service,endpoints -n database postgresql

# Check TLS secret
kubectl get secret -n database postgresql-tls-ca

# Test connectivity
kubectl run pg-test --rm -it --restart=Never \
  --image=postgres:16-alpine \
  --namespace=database \
  -- pg_isready -h postgresql.database.svc.cluster.local
```

---

## Helm Chart Integration

### Chart Structure

Your Helm chart should follow this structure:

```
my-app/
├── Chart.yaml
├── values.yaml
├── values-production.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── secret.yaml          # Database credentials
│   └── configmap.yaml       # Non-sensitive config
```

### values.yaml

Define default database configuration:

```yaml
# PostgreSQL Configuration
postgresql:
  # Connection details (non-sensitive)
  host: postgresql.database.svc.cluster.local
  port: 5432
  database: ""  # Override in values-{env}.yaml
  sslmode: require

  # Credentials (will be overridden by CI/CD)
  username: ""
  password: ""

  # TLS Configuration
  tls:
    enabled: true
    caSecretName: postgresql-tls-ca
    caSecretNamespace: database
    mountPath: /etc/postgresql/ssl

# Application configuration
replicaCount: 2

image:
  repository: ghcr.io/myorg/my-app
  tag: latest
  pullPolicy: IfNotPresent

resources:
  limits:
    memory: "512Mi"
    cpu: "500m"
  requests:
    memory: "256Mi"
    cpu: "250m"
```

### values-production.yaml

Environment-specific overrides:

```yaml
# Production-specific values
replicaCount: 3

postgresql:
  database: coaching  # Specific database name
  # username and password injected via CI/CD

image:
  tag: v1.2.3  # Specific version tag

resources:
  limits:
    memory: "1Gi"
    cpu: "1000m"
  requests:
    memory: "512Mi"
    cpu: "500m"
```

### templates/secret.yaml

Create secret from Helm values:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "my-app.fullname" . }}-postgres
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
type: Opaque
stringData:
  POSTGRES_HOST: {{ .Values.postgresql.host | quote }}
  POSTGRES_PORT: {{ .Values.postgresql.port | quote }}
  POSTGRES_DB: {{ .Values.postgresql.database | quote }}
  POSTGRES_USER: {{ .Values.postgresql.username | quote }}
  POSTGRES_PASSWORD: {{ .Values.postgresql.password | quote }}
  POSTGRES_SSLMODE: {{ .Values.postgresql.sslmode | quote }}
  {{- if .Values.postgresql.tls.enabled }}
  PGSSLROOTCERT: {{ .Values.postgresql.tls.mountPath }}/ca.crt
  {{- end }}
  # Construct full connection string
  DATABASE_URL: "postgresql://{{ .Values.postgresql.username }}:{{ .Values.postgresql.password }}@{{ .Values.postgresql.host }}:{{ .Values.postgresql.port }}/{{ .Values.postgresql.database }}?sslmode={{ .Values.postgresql.sslmode }}"
```

### templates/deployment.yaml

Reference the secret in your deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-app.fullname" . }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "my-app.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "my-app.selectorLabels" . | nindent 8 }}
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}

        # Load database credentials from secret
        envFrom:
        - secretRef:
            name: {{ include "my-app.fullname" . }}-postgres

        # Or load individual env vars:
        # env:
        # - name: POSTGRES_PASSWORD
        #   valueFrom:
        #     secretKeyRef:
        #       name: {{ include "my-app.fullname" . }}-postgres
        #       key: POSTGRES_PASSWORD

        {{- if .Values.postgresql.tls.enabled }}
        # Mount TLS CA certificate
        volumeMounts:
        - name: postgres-ca
          mountPath: {{ .Values.postgresql.tls.mountPath }}
          readOnly: true
        {{- end }}

        ports:
        - name: http
          containerPort: 8080
          protocol: TCP

        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10

        readinessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 5
          periodSeconds: 5

        resources:
          {{- toYaml .Values.resources | nindent 10 }}

      {{- if .Values.postgresql.tls.enabled }}
      # Volume for TLS CA certificate
      volumes:
      - name: postgres-ca
        secret:
          secretName: {{ .Values.postgresql.tls.caSecretName }}
          items:
          - key: ca.crt
            path: ca.crt
      {{- end }}
```

---

## Secret Management

### Option 1: GitHub Actions Secrets

Store database credentials in GitHub repository secrets.

#### 1. Add Secrets to GitHub

Navigate to: `Settings → Secrets and variables → Actions → New repository secret`

Add the following secrets:

```
POSTGRES_USERNAME_COACHING = coaching_user
POSTGRES_PASSWORD_COACHING = <generated-password>
POSTGRES_USERNAME_RESUME = resume_user
POSTGRES_PASSWORD_RESUME = <generated-password>
POSTGRES_USERNAME_DASHBOARD = dashboard_user
POSTGRES_PASSWORD_DASHBOARD = <generated-password>
```

#### 2. Reference in GitHub Actions Workflow

```yaml
name: Deploy to Production

on:
  push:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v3
        with:
          version: '3.13.0'

      - name: Configure kubectl
        uses: azure/k8s-set-context@v3
        with:
          method: kubeconfig
          kubeconfig: ${{ secrets.KUBECONFIG }}

      - name: Deploy Coaching App
        run: |
          helm upgrade --install coaching-app ./helm/my-app \
            --namespace coaching \
            --create-namespace \
            --values ./helm/my-app/values-production.yaml \
            --set postgresql.username="${{ secrets.POSTGRES_USERNAME_COACHING }}" \
            --set postgresql.password="${{ secrets.POSTGRES_PASSWORD_COACHING }}" \
            --set postgresql.database="coaching" \
            --set image.tag="${{ github.sha }}" \
            --wait \
            --timeout 5m

      - name: Deploy Resume App
        run: |
          helm upgrade --install resume-app ./helm/my-app \
            --namespace resume \
            --create-namespace \
            --values ./helm/my-app/values-production.yaml \
            --set postgresql.username="${{ secrets.POSTGRES_USERNAME_RESUME }}" \
            --set postgresql.password="${{ secrets.POSTGRES_PASSWORD_RESUME }}" \
            --set postgresql.database="resume" \
            --set image.tag="${{ github.sha }}" \
            --wait \
            --timeout 5m
```

#### 3. Alternative: Using Helm Values File Override

Create a temporary values file during deployment:

```yaml
- name: Create secrets values file
  run: |
    cat > secrets.yaml <<EOF
    postgresql:
      username: ${{ secrets.POSTGRES_USERNAME_COACHING }}
      password: ${{ secrets.POSTGRES_PASSWORD_COACHING }}
      database: coaching
    EOF

- name: Deploy with secrets
  run: |
    helm upgrade --install coaching-app ./helm/my-app \
      --namespace coaching \
      --values ./helm/my-app/values-production.yaml \
      --values secrets.yaml \
      --set image.tag="${{ github.sha }}" \
      --wait

- name: Cleanup secrets file
  if: always()
  run: rm -f secrets.yaml
```

### Option 2: Infisical Integration

Use Infisical for centralized secret management with automatic sync to Kubernetes.

#### 1. Install Infisical Operator

```bash
# Add Infisical Helm repo
helm repo add infisical https://dl.infisical.com/helm
helm repo update

# Install Infisical operator
helm install infisical-operator infisical/infisical-operator \
  --namespace infisical-operator-system \
  --create-namespace
```

#### 2. Create Infisical Secret Store

```yaml
# infisical-secret-store.yaml
apiVersion: v1
kind: Secret
metadata:
  name: infisical-auth
  namespace: coaching
type: Opaque
stringData:
  clientId: ${{ secrets.INFISICAL_CLIENT_ID }}
  clientSecret: ${{ secrets.INFISICAL_CLIENT_SECRET }}

---
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: coaching-postgres-sync
  namespace: coaching
spec:
  # Authentication
  authentication:
    universalAuth:
      credentialsRef:
        secretName: infisical-auth
        secretNamespace: coaching

  # Infisical project settings
  projectSlug: lab-infrastructure
  environment: production
  secretPath: /postgresql/coaching

  # Managed Kubernetes secret
  managedSecretReference:
    secretName: coaching-app-postgres
    secretNamespace: coaching
    creationPolicy: Orphan

  # Sync behavior
  resyncInterval: 300  # 5 minutes
```

#### 3. Deploy with Infisical in GitHub Actions

```yaml
- name: Deploy Infisical Secret Sync
  run: |
    # Create Infisical auth secret
    kubectl create secret generic infisical-auth \
      --namespace coaching \
      --from-literal=clientId="${{ secrets.INFISICAL_CLIENT_ID }}" \
      --from-literal=clientSecret="${{ secrets.INFISICAL_CLIENT_SECRET }}" \
      --dry-run=client -o yaml | kubectl apply -f -

    # Deploy InfisicalSecret CRD
    kubectl apply -f k8s/infisical-secret-store.yaml

- name: Wait for secret sync
  run: |
    kubectl wait --for=condition=ready infisicalsecret/coaching-postgres-sync \
      --namespace coaching \
      --timeout=60s

- name: Deploy Application
  run: |
    helm upgrade --install coaching-app ./helm/my-app \
      --namespace coaching \
      --values ./helm/my-app/values-production.yaml \
      --set image.tag="${{ github.sha }}" \
      --wait
```

#### 4. Infisical Secrets Structure

In your Infisical project, create secrets with these keys:

**Project**: `lab-infrastructure`
**Environment**: `production`
**Path**: `/postgresql/coaching`

```
POSTGRES_HOST = postgresql.database.svc.cluster.local
POSTGRES_PORT = 5432
POSTGRES_DB = coaching
POSTGRES_USER = coaching_user
POSTGRES_PASSWORD = <secure-generated-password>
POSTGRES_SSLMODE = require
DATABASE_URL = postgresql://coaching_user:<password>@postgresql.database.svc.cluster.local:5432/coaching?sslmode=require
```

#### 5. Update Helm Chart to Use Infisical Secret

Modify `templates/deployment.yaml` to reference the Infisical-managed secret:

```yaml
spec:
  template:
    spec:
      containers:
      - name: {{ .Chart.Name }}
        envFrom:
        # Use Infisical-managed secret instead of Helm-generated one
        - secretRef:
            name: coaching-app-postgres  # Managed by InfisicalSecret
```

Remove or comment out `templates/secret.yaml` when using Infisical.

---

## GitHub Actions Deployment

### Complete Workflow Example

```yaml
name: Deploy Applications

on:
  push:
    branches: [main, develop]
  workflow_dispatch:

env:
  REGISTRY: ghcr.io

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    outputs:
      image-tag: ${{ steps.meta.outputs.tags }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Login to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ github.repository }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=sha,prefix={{branch}}-

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy:
    needs: build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'

    strategy:
      matrix:
        app:
          - name: coaching
            namespace: coaching
            database: coaching
            username_secret: POSTGRES_USERNAME_COACHING
            password_secret: POSTGRES_PASSWORD_COACHING
          - name: resume
            namespace: resume
            database: resume
            username_secret: POSTGRES_USERNAME_RESUME
            password_secret: POSTGRES_PASSWORD_RESUME

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Helm
        uses: azure/setup-helm@v3
        with:
          version: '3.13.0'

      - name: Configure kubectl
        run: |
          mkdir -p $HOME/.kube
          echo "${{ secrets.KUBECONFIG }}" | base64 -d > $HOME/.kube/config
          chmod 600 $HOME/.kube/config

      - name: Deploy ${{ matrix.app.name }}
        run: |
          helm upgrade --install ${{ matrix.app.name }}-app ./helm/app \
            --namespace ${{ matrix.app.namespace }} \
            --create-namespace \
            --values ./helm/app/values-production.yaml \
            --set postgresql.username="${{ secrets[matrix.app.username_secret] }}" \
            --set postgresql.password="${{ secrets[matrix.app.password_secret] }}" \
            --set postgresql.database="${{ matrix.app.database }}" \
            --set image.repository="${{ env.REGISTRY }}/${{ github.repository }}" \
            --set image.tag="${{ needs.build.outputs.image-tag }}" \
            --wait \
            --timeout 10m

      - name: Verify deployment
        run: |
          kubectl rollout status deployment/${{ matrix.app.name }}-app \
            --namespace ${{ matrix.app.namespace }} \
            --timeout=5m

      - name: Run database migrations
        if: matrix.app.migrations == true
        run: |
          kubectl create job ${{ matrix.app.name }}-migrate-$(date +%s) \
            --from=cronjob/${{ matrix.app.name }}-migrations \
            --namespace ${{ matrix.app.namespace }}
```

### Environment-Based Deployments

For staging vs production:

```yaml
jobs:
  deploy-staging:
    if: github.ref == 'refs/heads/develop'
    steps:
      - name: Deploy to Staging
        run: |
          helm upgrade --install coaching-app ./helm/app \
            --namespace coaching-staging \
            --values ./helm/app/values-staging.yaml \
            --set postgresql.username="${{ secrets.POSTGRES_USERNAME_COACHING_STAGING }}" \
            --set postgresql.password="${{ secrets.POSTGRES_PASSWORD_COACHING_STAGING }}" \
            --set postgresql.database="coaching_staging"

  deploy-production:
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Deploy to Production
        run: |
          helm upgrade --install coaching-app ./helm/app \
            --namespace coaching \
            --values ./helm/app/values-production.yaml \
            --set postgresql.username="${{ secrets.POSTGRES_USERNAME_COACHING }}" \
            --set postgresql.password="${{ secrets.POSTGRES_PASSWORD_COACHING }}" \
            --set postgresql.database="coaching"
```

---

## Example Applications

### Node.js Application

**Helm values:**
```yaml
# values.yaml
postgresql:
  host: postgresql.database.svc.cluster.local
  port: 5432
  database: coaching
  sslmode: require

  pool:
    min: 2
    max: 10
```

**Application code:**
```javascript
// config/database.js
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.POSTGRES_HOST,
  port: parseInt(process.env.POSTGRES_PORT),
  database: process.env.POSTGRES_DB,
  user: process.env.POSTGRES_USER,
  password: process.env.POSTGRES_PASSWORD,
  ssl: process.env.PGSSLROOTCERT ? {
    rejectUnauthorized: true,
    ca: require('fs').readFileSync(process.env.PGSSLROOTCERT)
  } : false,
  min: 2,
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

module.exports = pool;
```

### Python/Django Application

**Helm values:**
```yaml
# values.yaml
postgresql:
  host: postgresql.database.svc.cluster.local
  port: 5432
  database: resume
  sslmode: require

django:
  migrateOnDeploy: true
  collectStaticOnDeploy: true
```

**settings.py:**
```python
import os

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'HOST': os.environ['POSTGRES_HOST'],
        'PORT': os.environ['POSTGRES_PORT'],
        'NAME': os.environ['POSTGRES_DB'],
        'USER': os.environ['POSTGRES_USER'],
        'PASSWORD': os.environ['POSTGRES_PASSWORD'],
        'OPTIONS': {
            'sslmode': os.environ.get('POSTGRES_SSLMODE', 'require'),
            'sslrootcert': os.environ.get('PGSSLROOTCERT', ''),
            'connect_timeout': 5,
        },
        'CONN_MAX_AGE': 600,
    }
}
```

**Helm deployment with migrations:**
```yaml
# templates/job-migrate.yaml
{{- if .Values.django.migrateOnDeploy }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "app.fullname" . }}-migrate-{{ .Release.Revision }}
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-weight": "1"
    "helm.sh/hook-delete-policy": before-hook-creation
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: migrate
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        command: ["python", "manage.py", "migrate"]
        envFrom:
        - secretRef:
            name: {{ include "app.fullname" . }}-postgres
{{- end }}
```

---

## Migration from Existing Databases

### 1. Backup Existing Database

```bash
# From old database
pg_dump -h old-database-host -U old-user -d old_database -F c -f backup.dump

# Or use DATABASE_URL
pg_dump $OLD_DATABASE_URL -F c -f backup.dump
```

### 2. Restore to New Database

```bash
# Copy to tower-pc
scp backup.dump bearf@10.0.0.249:/tmp/

# Restore on tower-pc
ssh bearf@10.0.0.249
sudo docker exec -i postgresql pg_restore \
  -U coaching_user \
  -d coaching \
  --no-owner \
  --no-acl \
  --clean \
  --if-exists \
  < /tmp/backup.dump

# Cleanup
rm /tmp/backup.dump
```

### 3. Update Application Configuration

**Before (old database):**
```yaml
# GitHub Actions secrets
DATABASE_URL: postgresql://user:pass@old-host.com:5432/mydb
```

**After (new database):**
```yaml
# GitHub Actions secrets
POSTGRES_USERNAME_COACHING: coaching_user
POSTGRES_PASSWORD_COACHING: <new-password>

# Helm values
postgresql:
  host: postgresql.database.svc.cluster.local
  database: coaching
```

### 4. Deploy Updated Configuration

```bash
# Deploy with new database settings
helm upgrade --install coaching-app ./helm/app \
  --namespace coaching \
  --values values-production.yaml \
  --set postgresql.username="${POSTGRES_USERNAME}" \
  --set postgresql.password="${POSTGRES_PASSWORD}" \
  --set postgresql.database="coaching"
```

### 5. Verify Migration

```bash
# Check application logs
kubectl logs -n coaching deployment/coaching-app --tail=100

# Test database connectivity from pod
kubectl exec -n coaching deployment/coaching-app -- \
  psql -h postgresql.database.svc.cluster.local -U coaching_user -d coaching -c "SELECT COUNT(*) FROM your_table;"
```

---

## Troubleshooting

### Connection Refused

**Symptom:** Application can't connect to database

**Debug steps:**
```bash
# 1. Check service and endpoints
kubectl get service,endpoints -n database postgresql

# 2. Test from application namespace
kubectl run debug -n coaching --rm -it --restart=Never \
  --image=postgres:16-alpine \
  -- pg_isready -h postgresql.database.svc.cluster.local

# 3. Check application logs
kubectl logs -n coaching deployment/coaching-app --tail=50

# 4. Verify DNS resolution
kubectl run debug -n coaching --rm -it --restart=Never \
  --image=busybox \
  -- nslookup postgresql.database.svc.cluster.local
```

### Authentication Failed

**Symptom:** `FATAL: password authentication failed for user`

**Debug steps:**
```bash
# 1. Verify secret exists and has correct values
kubectl get secret -n coaching coaching-app-postgres -o yaml

# 2. Decode and check username
kubectl get secret -n coaching coaching-app-postgres \
  -o jsonpath='{.data.POSTGRES_USER}' | base64 -d

# 3. Test credentials manually
kubectl run psql-test -n coaching --rm -it --restart=Never \
  --image=postgres:16-alpine \
  -- psql "postgresql://coaching_user:PASSWORD@postgresql.database.svc.cluster.local/coaching"

# 4. Check GitHub Actions logs for secret injection
# Ensure secrets are correctly passed to helm
```

### SSL/TLS Errors

**Symptom:** `SSL error` or certificate verification failed

**Debug steps:**
```bash
# 1. Check TLS secret in database namespace
kubectl get secret -n database postgresql-tls-ca

# 2. Verify CA cert is mounted in pod
kubectl exec -n coaching deployment/coaching-app -- \
  cat /etc/postgresql/ssl/ca.crt

# 3. Test with sslmode=require
kubectl run psql-test -n coaching --rm -it --restart=Never \
  --image=postgres:16-alpine \
  -- psql "postgresql://user:pass@postgresql.database.svc.cluster.local/coaching?sslmode=require"
```

### Helm Deployment Issues

**Symptom:** Helm upgrade fails or secrets not updating

```bash
# 1. Check Helm release status
helm list -n coaching

# 2. Get Helm release history
helm history coaching-app -n coaching

# 3. View generated manifests
helm get manifest coaching-app -n coaching

# 4. Debug Helm values
helm get values coaching-app -n coaching

# 5. Dry-run to see what would be deployed
helm upgrade --install coaching-app ./helm/app \
  --namespace coaching \
  --values values-production.yaml \
  --set postgresql.password="test" \
  --dry-run --debug
```

### Pod Not Starting After Database Update

```bash
# 1. Check pod status
kubectl get pods -n coaching

# 2. Describe pod for events
kubectl describe pod -n coaching <pod-name>

# 3. Check logs
kubectl logs -n coaching <pod-name> --previous

# 4. Force restart deployment
kubectl rollout restart deployment/coaching-app -n coaching

# 5. Delete and recreate pods
kubectl delete pod -n coaching -l app=coaching-app
```

---

## Security Best Practices

### 1. Use Different Credentials Per Environment

**Staging:**
```yaml
# GitHub Secrets
POSTGRES_USERNAME_COACHING_STAGING: coaching_user_staging
POSTGRES_PASSWORD_COACHING_STAGING: <different-password>
```

**Production:**
```yaml
# GitHub Secrets
POSTGRES_USERNAME_COACHING: coaching_user
POSTGRES_PASSWORD_COACHING: <different-password>
```

### 2. Rotate Passwords Regularly

**Using GitHub Actions scheduled workflow:**

```yaml
name: Rotate Database Passwords

on:
  schedule:
    - cron: '0 0 1 * *'  # Monthly on the 1st
  workflow_dispatch:

jobs:
  rotate:
    runs-on: ubuntu-latest
    steps:
      - name: Generate new password
        id: gen-password
        run: |
          NEW_PASS=$(openssl rand -base64 32)
          echo "::add-mask::$NEW_PASS"
          echo "new_password=$NEW_PASS" >> $GITHUB_OUTPUT

      - name: Update database password
        run: |
          ssh bearf@10.0.0.249 << 'EOF'
          sudo docker exec postgresql psql -U postgres -c \
            "ALTER USER coaching_user WITH PASSWORD '${{ steps.gen-password.outputs.new_password }}';"
          EOF

      - name: Update GitHub secret
        uses: hmanzur/actions-set-secret@v2.0.0
        with:
          name: POSTGRES_PASSWORD_COACHING
          value: ${{ steps.gen-password.outputs.new_password }}
          repository: ${{ github.repository }}
          token: ${{ secrets.REPO_ADMIN_TOKEN }}

      - name: Redeploy application with new secret
        run: |
          # Trigger deployment workflow
          gh workflow run deploy.yml
```

### 3. Principle of Least Privilege

Create read-only users for analytics/reporting:

```sql
-- Create read-only user
CREATE USER analytics_user WITH PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE coaching TO analytics_user;
GRANT USAGE ON SCHEMA public TO analytics_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO analytics_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO analytics_user;
```

### 4. Connection Pooling

Configure appropriate pool sizes based on application load:

**Low traffic (< 100 req/min):**
```yaml
postgresql:
  pool:
    min: 2
    max: 10
```

**Medium traffic (100-1000 req/min):**
```yaml
postgresql:
  pool:
    min: 5
    max: 20
```

**High traffic (> 1000 req/min):**
```yaml
postgresql:
  pool:
    min: 10
    max: 50
```

### 5. Secure Secret Storage

**Never commit secrets to git:**
```bash
# .gitignore
secrets.yaml
*.secret
*-secrets.yaml
values-secrets.yaml
```

**Use encrypted secrets for GitOps:**
- Sealed Secrets
- SOPS (with Age or PGP)
- Infisical
- External Secrets Operator

### 6. Audit Access

Monitor database connections:

```sql
-- View active connections
SELECT
  datname,
  usename,
  application_name,
  client_addr,
  state,
  query_start
FROM pg_stat_activity
WHERE datname = 'coaching'
ORDER BY query_start DESC;

-- Check failed login attempts (enable log_connections in postgresql.conf)
-- View logs: ssh bearf@10.0.0.249 "sudo docker logs postgresql | grep FATAL"
```

---

## Additional Resources

- **Helm Documentation**: https://helm.sh/docs/
- **PostgreSQL Connection Strings**: https://www.postgresql.org/docs/16/libpq-connect.html
- **GitHub Actions Secrets**: https://docs.github.com/en/actions/security-guides/encrypted-secrets
- **Infisical Documentation**: https://infisical.com/docs
- **External Secrets Operator**: https://external-secrets.io/

---

## Getting Started Checklist

- [ ] Database credentials added to GitHub Actions secrets or Infisical
- [ ] Helm chart created with PostgreSQL configuration
- [ ] `values-production.yaml` configured with correct database name
- [ ] GitHub Actions workflow updated to pass secrets to Helm
- [ ] TLS CA certificate volume mounted in deployment (if using TLS verification)
- [ ] Application code configured to use environment variables
- [ ] Database migration strategy planned (if migrating from existing DB)
- [ ] Connection pooling configured appropriately
- [ ] Monitoring and logging configured
- [ ] Deployment tested in staging environment

---

**Last Updated**: 2026-01-01
**PostgreSQL Version**: 16.11
**Kubernetes Version**: 1.28
**Helm Version**: 3.13+
