# PostgreSQL Service Integration Guide

This guide covers integrating your Kubernetes applications with the PostgreSQL database server running on tower-pc.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Database Access Patterns](#database-access-patterns)
5. [Creating Application Secrets](#creating-application-secrets)
6. [Example Integrations](#example-integrations)
7. [Migration from Existing Databases](#migration-from-existing-databases)
8. [Troubleshooting](#troubleshooting)
9. [Security Best Practices](#security-best-practices)

---

## Overview

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Kubernetes Cluster (10.244.0.0/16 pod network)             │
│                                                              │
│  ┌──────────────┐         ┌──────────────────────────┐     │
│  │ Application  │────────▶│ Service: postgresql      │     │
│  │ Pod          │         │ (database namespace)     │     │
│  └──────────────┘         └──────────────────────────┘     │
│                                      │                       │
└──────────────────────────────────────┼───────────────────────┘
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

1. **Kubernetes Cluster**: Applications must be running in the Kubernetes cluster
2. **Database Namespace**: The `database` namespace must exist (created during PostgreSQL setup)
3. **TLS Certificate**: The `postgresql-tls-ca` secret exists in the `database` namespace
4. **Database Credentials**: Contact the infrastructure admin to get your database credentials

### Verify Prerequisites

```bash
# Check namespace
kubectl get namespace database

# Check service
kubectl get service -n database postgresql

# Check TLS secret
kubectl get secret -n database postgresql-tls-ca

# Test connectivity
kubectl run pg-test --rm -it --restart=Never \
  --image=postgres:16-alpine \
  --namespace=database \
  -- pg_isready -h postgresql.database.svc.cluster.local
```

---

## Quick Start

### 1. Create Application Secret

Create a Kubernetes secret containing your database credentials:

```bash
kubectl create secret generic my-app-postgres \
  --namespace=my-namespace \
  --from-literal=POSTGRES_HOST=postgresql.database.svc.cluster.local \
  --from-literal=POSTGRES_PORT=5432 \
  --from-literal=POSTGRES_DB=my_database \
  --from-literal=POSTGRES_USER=my_user \
  --from-literal=POSTGRES_PASSWORD='my_secure_password' \
  --from-literal=DATABASE_URL='postgresql://my_user:my_secure_password@postgresql.database.svc.cluster.local:5432/my_database?sslmode=require'
```

### 2. Mount Secret in Deployment

Add the secret to your deployment YAML:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-namespace
spec:
  template:
    spec:
      containers:
      - name: my-app
        image: my-app:latest
        envFrom:
        - secretRef:
            name: my-app-postgres
        # OR mount individual values:
        env:
        - name: POSTGRES_HOST
          valueFrom:
            secretKeyRef:
              name: my-app-postgres
              key: POSTGRES_HOST
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: my-app-postgres
              key: POSTGRES_PASSWORD
```

### 3. Configure TLS (Optional but Recommended)

To use the CA certificate for TLS verification:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: my-app
        image: my-app:latest
        env:
        - name: PGSSLROOTCERT
          value: /etc/postgresql/ca.crt
        volumeMounts:
        - name: postgres-ca
          mountPath: /etc/postgresql
          readOnly: true
      volumes:
      - name: postgres-ca
        secret:
          secretName: postgresql-tls-ca
```

---

## Database Access Patterns

### Pattern 1: Environment Variables

Most applications support PostgreSQL connection via environment variables:

```yaml
env:
- name: POSTGRES_HOST
  value: postgresql.database.svc.cluster.local
- name: POSTGRES_PORT
  value: "5432"
- name: POSTGRES_DB
  value: my_database
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: my-app-postgres
      key: POSTGRES_USER
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: my-app-postgres
      key: POSTGRES_PASSWORD
```

### Pattern 2: Connection String / DATABASE_URL

For applications using connection strings (Rails, Django, etc.):

```yaml
env:
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: my-app-postgres
      key: DATABASE_URL
```

The connection string format:
```
postgresql://username:password@postgresql.database.svc.cluster.local:5432/database_name?sslmode=require
```

### Pattern 3: ConfigMap + Secret

Separate non-sensitive config from credentials:

```yaml
# ConfigMap for non-sensitive values
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-app-postgres-config
data:
  POSTGRES_HOST: postgresql.database.svc.cluster.local
  POSTGRES_PORT: "5432"
  POSTGRES_DB: my_database

---
# Secret for sensitive values
apiVersion: v1
kind: Secret
metadata:
  name: my-app-postgres-secret
type: Opaque
stringData:
  POSTGRES_USER: my_user
  POSTGRES_PASSWORD: my_secure_password

---
# Deployment using both
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: my-app
        envFrom:
        - configMapRef:
            name: my-app-postgres-config
        - secretRef:
            name: my-app-postgres-secret
```

---

## Creating Application Secrets

### Method 1: Using kubectl (Quick)

```bash
# Set your credentials
DB_NAME="coaching"
DB_USER="coaching_user"
DB_PASSWORD="$(ansible-vault view ansible/group_vars/all/vault.yml | grep coaching_user_password | cut -d'"' -f2)"

# Create the secret
kubectl create secret generic coaching-app-postgres \
  --namespace=coaching \
  --from-literal=POSTGRES_HOST=postgresql.database.svc.cluster.local \
  --from-literal=POSTGRES_PORT=5432 \
  --from-literal=POSTGRES_DB="${DB_NAME}" \
  --from-literal=POSTGRES_USER="${DB_USER}" \
  --from-literal=POSTGRES_PASSWORD="${DB_PASSWORD}" \
  --from-literal=DATABASE_URL="postgresql://${DB_USER}:${DB_PASSWORD}@postgresql.database.svc.cluster.local:5432/${DB_NAME}?sslmode=require"
```

### Method 2: Using YAML with Infisical/External Secrets

For production, use a secrets management solution:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-postgres
  namespace: my-namespace
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: infisical-secret-store
    kind: SecretStore
  target:
    name: my-app-postgres
  data:
  - secretKey: POSTGRES_HOST
    remoteRef:
      key: postgres/my-app/host
  - secretKey: POSTGRES_PORT
    remoteRef:
      key: postgres/my-app/port
  - secretKey: POSTGRES_DB
    remoteRef:
      key: postgres/my-app/database
  - secretKey: POSTGRES_USER
    remoteRef:
      key: postgres/my-app/username
  - secretKey: POSTGRES_PASSWORD
    remoteRef:
      key: postgres/my-app/password
```

### Method 3: Using Sealed Secrets (Git-safe)

```bash
# Install kubeseal if not already installed
# brew install kubeseal  # macOS
# or download from: https://github.com/bitnami-labs/sealed-secrets/releases

# Create a temporary secret
kubectl create secret generic my-app-postgres \
  --namespace=my-namespace \
  --from-literal=POSTGRES_PASSWORD="${DB_PASSWORD}" \
  --dry-run=client -o yaml > temp-secret.yaml

# Seal it
kubeseal < temp-secret.yaml > sealed-secret.yaml

# Clean up
rm temp-secret.yaml

# Commit sealed-secret.yaml to git
git add sealed-secret.yaml
git commit -m "Add sealed database secret"
```

---

## Example Integrations

### Node.js / Express Application

**Dockerfile:**
```dockerfile
FROM node:18-alpine

# Install PostgreSQL client for health checks
RUN apk add --no-cache postgresql-client

WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY . .

EXPOSE 3000
CMD ["node", "server.js"]
```

**Application Code (server.js):**
```javascript
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.POSTGRES_HOST,
  port: process.env.POSTGRES_PORT,
  database: process.env.POSTGRES_DB,
  user: process.env.POSTGRES_USER,
  password: process.env.POSTGRES_PASSWORD,
  ssl: {
    rejectUnauthorized: true,
    ca: process.env.PGSSLROOTCERT
      ? require('fs').readFileSync(process.env.PGSSLROOTCERT)
      : undefined
  }
});

// Test connection
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('Database connection error:', err);
  } else {
    console.log('Database connected:', res.rows[0]);
  }
});
```

**Kubernetes Deployment:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nodejs-app
  namespace: coaching
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nodejs-app
  template:
    metadata:
      labels:
        app: nodejs-app
    spec:
      containers:
      - name: app
        image: my-registry/nodejs-app:latest
        ports:
        - containerPort: 3000
        envFrom:
        - secretRef:
            name: coaching-app-postgres
        env:
        - name: PGSSLROOTCERT
          value: /etc/postgresql/ca.crt
        volumeMounts:
        - name: postgres-ca
          mountPath: /etc/postgresql
          readOnly: true
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -h $POSTGRES_HOST -U $POSTGRES_USER
          initialDelaySeconds: 10
          periodSeconds: 30
      volumes:
      - name: postgres-ca
        secret:
          secretName: postgresql-tls-ca
```

### Python / Django Application

**settings.py:**
```python
import os

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'HOST': os.environ.get('POSTGRES_HOST'),
        'PORT': os.environ.get('POSTGRES_PORT', '5432'),
        'NAME': os.environ.get('POSTGRES_DB'),
        'USER': os.environ.get('POSTGRES_USER'),
        'PASSWORD': os.environ.get('POSTGRES_PASSWORD'),
        'OPTIONS': {
            'sslmode': 'require',
            'sslrootcert': os.environ.get('PGSSLROOTCERT', ''),
        },
    }
}
```

**Deployment:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: django-app
  namespace: resume
spec:
  replicas: 3
  selector:
    matchLabels:
      app: django-app
  template:
    metadata:
      labels:
        app: django-app
    spec:
      initContainers:
      - name: migrate
        image: my-registry/django-app:latest
        command: ['python', 'manage.py', 'migrate']
        envFrom:
        - secretRef:
            name: resume-app-postgres
        env:
        - name: PGSSLROOTCERT
          value: /etc/postgresql/ca.crt
        volumeMounts:
        - name: postgres-ca
          mountPath: /etc/postgresql
          readOnly: true
      containers:
      - name: app
        image: my-registry/django-app:latest
        ports:
        - containerPort: 8000
        envFrom:
        - secretRef:
            name: resume-app-postgres
        env:
        - name: PGSSLROOTCERT
          value: /etc/postgresql/ca.crt
        volumeMounts:
        - name: postgres-ca
          mountPath: /etc/postgresql
          readOnly: true
      volumes:
      - name: postgres-ca
        secret:
          secretName: postgresql-tls-ca
```

### Go Application

**main.go:**
```go
package main

import (
    "database/sql"
    "fmt"
    "log"
    "os"

    _ "github.com/lib/pq"
)

func main() {
    connStr := fmt.Sprintf(
        "host=%s port=%s user=%s password=%s dbname=%s sslmode=require sslrootcert=%s",
        os.Getenv("POSTGRES_HOST"),
        os.Getenv("POSTGRES_PORT"),
        os.Getenv("POSTGRES_USER"),
        os.Getenv("POSTGRES_PASSWORD"),
        os.Getenv("POSTGRES_DB"),
        os.Getenv("PGSSLROOTCERT"),
    )

    db, err := sql.Open("postgres", connStr)
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()

    err = db.Ping()
    if err != nil {
        log.Fatal(err)
    }

    log.Println("Successfully connected to database!")
}
```

---

## Migration from Existing Databases

### Option 1: pg_dump / pg_restore

**Export from old database:**
```bash
# From the old database server
pg_dump -h old-host -U old-user -d old_database -F c -f backup.dump
```

**Import to new database:**
```bash
# Copy to tower-pc
scp backup.dump bearf@10.0.0.249:/tmp/

# Import on tower-pc
ssh bearf@10.0.0.249
sudo docker exec -i postgresql pg_restore \
  -U coaching_user \
  -d coaching \
  --no-owner \
  --no-acl \
  < /tmp/backup.dump
```

### Option 2: Direct Database Copy

```bash
# Using psql piping
pg_dump -h old-host -U old-user old_database | \
  kubectl run pg-restore --rm -i --restart=Never \
    --image=postgres:16-alpine \
    --namespace=database \
    -- psql -h postgresql.database.svc.cluster.local \
         -U coaching_user \
         -d coaching
```

### Option 3: SQL File Migration

```bash
# Export as SQL
pg_dump -h old-host -U old-user -d old_database > export.sql

# Import via kubectl
kubectl run psql-import --rm -i --restart=Never \
  --image=postgres:16-alpine \
  --namespace=database \
  -- psql -h postgresql.database.svc.cluster.local \
       -U coaching_user \
       -d coaching < export.sql
```

---

## Troubleshooting

### Connection Refused

**Symptom:** `connection refused` or `could not connect to server`

**Checks:**
```bash
# 1. Verify service exists
kubectl get service -n database postgresql

# 2. Verify endpoints are configured
kubectl get endpoints -n database postgresql

# 3. Test from a pod
kubectl run debug --rm -it --restart=Never \
  --image=postgres:16-alpine \
  --namespace=database \
  -- psql -h postgresql.database.svc.cluster.local -U postgres -l
```

### Authentication Failed

**Symptom:** `authentication failed for user`

**Checks:**
```bash
# 1. Verify credentials in secret
kubectl get secret my-app-postgres -n my-namespace -o yaml | \
  yq '.data.POSTGRES_PASSWORD' | base64 -d

# 2. Test credentials directly
kubectl run psql-test --rm -it --restart=Never \
  --image=postgres:16-alpine \
  --namespace=database \
  -- psql "postgresql://coaching_user:PASSWORD@postgresql.database.svc.cluster.local:5432/coaching?sslmode=require"
```

### SSL/TLS Errors

**Symptom:** `SSL error` or `certificate verify failed`

**Checks:**
```bash
# 1. Verify CA secret exists
kubectl get secret -n database postgresql-tls-ca

# 2. Check certificate in application pod
kubectl exec -it my-app-pod -- cat /etc/postgresql/ca.crt

# 3. Test with sslmode=require
kubectl run ssl-test --rm -it --restart=Never \
  --image=postgres:16-alpine \
  --namespace=database \
  -- psql "postgresql://user:pass@postgresql.database.svc.cluster.local:5432/db?sslmode=require"
```

### Slow Queries

**Check connection pooling:**
```sql
-- Connect to database
SELECT count(*), state FROM pg_stat_activity GROUP BY state;

-- Check slow queries
SELECT pid, now() - query_start as duration, query
FROM pg_stat_activity
WHERE state = 'active'
ORDER BY duration DESC;
```

### Database Doesn't Exist

**Create new database (requires admin access):**
```bash
# SSH to tower-pc
ssh bearf@10.0.0.249

# Create database
sudo docker exec -it postgresql psql -U postgres -c "CREATE DATABASE my_new_db;"

# Create user
sudo docker exec -it postgresql psql -U postgres -c "CREATE USER my_user WITH PASSWORD 'secure_password';"

# Grant privileges
sudo docker exec -it postgresql psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE my_new_db TO my_user;"
```

---

## Security Best Practices

### 1. Use Kubernetes Secrets

✅ **DO:**
```yaml
env:
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: my-app-postgres
      key: POSTGRES_PASSWORD
```

❌ **DON'T:**
```yaml
env:
- name: POSTGRES_PASSWORD
  value: "plaintext_password"  # Never do this!
```

### 2. Enable TLS Verification

✅ **DO:**
```
postgresql://user:pass@host:5432/db?sslmode=require
```

❌ **DON'T:**
```
postgresql://user:pass@host:5432/db?sslmode=disable
```

### 3. Use Connection Pooling

Limit database connections from your application:

**Node.js:**
```javascript
const pool = new Pool({
  max: 20,  // Maximum connections
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});
```

**Python (SQLAlchemy):**
```python
engine = create_engine(
    DATABASE_URL,
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True
)
```

### 4. Principle of Least Privilege

Each application should have its own database user with minimal permissions:

```sql
-- Create read-only user
CREATE USER readonly_user WITH PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE my_database TO readonly_user;
GRANT USAGE ON SCHEMA public TO readonly_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_user;
```

### 5. Regular Password Rotation

Update passwords periodically:

```bash
# Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# Update in database
ssh bearf@10.0.0.249
sudo docker exec -it postgresql psql -U postgres -c \
  "ALTER USER coaching_user WITH PASSWORD '${NEW_PASSWORD}';"

# Update Kubernetes secret
kubectl create secret generic coaching-app-postgres \
  --from-literal=POSTGRES_PASSWORD="${NEW_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods to pick up new secret
kubectl rollout restart deployment/coaching-app -n coaching
```

### 6. Network Policies (Optional)

Restrict database access to specific namespaces:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgres-access
  namespace: database
spec:
  podSelector:
    matchLabels:
      app: postgresql-endpoint
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          database-access: "true"
    ports:
    - protocol: TCP
      port: 5432
```

---

## Additional Resources

- **PostgreSQL Documentation**: https://www.postgresql.org/docs/16/
- **Kubernetes Secrets**: https://kubernetes.io/docs/concepts/configuration/secret/
- **Connection Pooling Best Practices**: https://www.postgresql.org/docs/16/runtime-config-connection.html
- **TLS Configuration**: https://www.postgresql.org/docs/16/ssl-tcp.html

---

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review PostgreSQL logs: `ssh bearf@10.0.0.249 "sudo docker logs postgresql"`
3. Contact the infrastructure team

---

**Last Updated**: 2026-01-01
**PostgreSQL Version**: 16.11
**Kubernetes Version**: 1.28
