# PostgreSQL External Database

This directory contains Kubernetes manifests for accessing the PostgreSQL instance running on tower-pc outside the cluster.

## Architecture

- **Location**: tower-pc (10.0.0.249) - runs as Docker container
- **Storage**: `/mnt/nfs-storage/postgresql` (bcache-accelerated HDD)
- **Backups**: ZFS dataset `storage/postgresql-backups`
- **Security**: TLS with self-signed CA, password authentication

## Deployment

### Deploy PostgreSQL on tower-pc

```bash
cd ansible
ansible-playbook playbooks/setup-postgresql.yml --ask-vault-pass
```

### Apply Kubernetes manifests

```bash
kubectl apply -f k8s-manifests/postgresql/namespace.yaml
kubectl apply -f k8s-manifests/postgresql/service.yaml
```

### Create application secrets

Secrets are managed via the Ansible playbook and include:
- `postgresql-credentials` - Connection strings and credentials
- `postgresql-tls-ca` - CA certificate for TLS verification

To create a secret manually:

```bash
kubectl create secret generic my-app-db -n my-namespace \
  --from-literal=POSTGRES_HOST=postgresql.database.svc.cluster.local \
  --from-literal=POSTGRES_PORT=5432 \
  --from-literal=POSTGRES_USER=myuser \
  --from-literal=POSTGRES_PASSWORD=mypassword \
  --from-literal=POSTGRES_DB=mydb \
  --from-literal=DATABASE_URL="postgresql://myuser:mypassword@postgresql.database.svc.cluster.local:5432/mydb?sslmode=require"
```

## Usage in Pods

### Environment variables from Secret

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
    - name: app
      image: my-app:latest
      envFrom:
        - secretRef:
            name: my-app-db
```

### Connection string example

```
postgresql://user:password@postgresql.database.svc.cluster.local:5432/dbname?sslmode=require
```

### Python example

```python
import psycopg2
import os

conn = psycopg2.connect(os.environ['DATABASE_URL'])
```

### Node.js example

```javascript
const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
```

## Network Configuration

If tower-pc network changes (e.g., second NIC added):

1. Update IP in `service.yaml` Endpoints section
2. Apply: `kubectl apply -f k8s-manifests/postgresql/service.yaml`

## Backup and Recovery

### Manual backup

```bash
ssh tower-pc "sudo /usr/local/bin/backup-postgresql.sh"
```

### Restore from backup

```bash
# List available backups
ssh tower-pc "ls -lh /storage/postgresql-backups/"

# Restore specific database
ssh tower-pc "docker exec -i postgresql pg_restore -U postgres -d dbname" < backup.dump
```

### ZFS snapshots

```bash
# List snapshots
ssh tower-pc "zfs list -t snapshot | grep postgresql-backups"

# Rollback to snapshot
ssh tower-pc "zfs rollback storage/postgresql-backups@backup_20260101_030000"
```

## Monitoring

### Check PostgreSQL health

```bash
ssh tower-pc "docker exec postgresql pg_isready -U postgres"
```

### View logs

```bash
ssh tower-pc "docker logs postgresql"
```

### Resource usage

```bash
ssh tower-pc "systemctl status postgresql.slice"
```

## Troubleshooting

### Test connectivity from k8s

```bash
kubectl run pg-test --rm -it --restart=Never --image=postgres:16-alpine \
  --env="PGPASSWORD=yourpassword" \
  -- psql -h postgresql.database.svc.cluster.local -U postgres -c "SELECT version();"
```

### Verify TLS

```bash
kubectl run ssl-test --rm -it --restart=Never --image=alpine \
  -- sh -c "apk add openssl && openssl s_client -connect 10.0.0.249:5432 -starttls postgres"
```

### Common issues

1. **Connection refused**: Check firewall rules on tower-pc
2. **TLS errors**: Verify CA certificate in pod, check `sslmode` parameter
3. **Authentication failed**: Verify password, check `pg_hba.conf` rules
4. **DNS resolution**: Ensure `database` namespace exists and service is created
