# Garage S3 Object Storage

This directory contains Kubernetes manifests for accessing the Garage S3-compatible object storage running on tower-pc.

## Architecture

- **Location**: tower-pc (10.0.0.249) - runs as Docker container
- **Image**: `dxflrs/garage:v2.1.0`
- **Storage**: ZFS RAID-Z1 on 3x2TB HDDs (~4TB usable)
- **Metadata**: `/var/lib/garage/meta` (system SSD)
- **API**: S3-compatible (AWS SDK compatible)

## Deployment

### Deploy Garage on tower-pc

```bash
cd ansible
ansible-playbook playbooks/setup-garage.yml -v
```

### Apply Kubernetes manifests

```bash
# Using Kustomize (recommended)
kubectl apply -k kubernetes/base/garage

# Or apply individual files
kubectl apply -f kubernetes/base/garage/namespace.yaml
kubectl apply -f kubernetes/base/garage/service.yaml
```

## Usage in Pods

### Connection Details

- **Endpoint**: `http://garage.storage.svc.cluster.local:3900`
- **Region**: `lab-garage`
- **Access Style**: Path-style (not virtual-hosted)

### Create a Secret with S3 Credentials

```bash
kubectl create secret generic s3-credentials -n my-namespace \
  --from-literal=AWS_ACCESS_KEY_ID=<key-id> \
  --from-literal=AWS_SECRET_ACCESS_KEY=<secret-key> \
  --from-literal=AWS_ENDPOINT_URL=http://garage.storage.svc.cluster.local:3900 \
  --from-literal=AWS_REGION=lab-garage
```

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
            name: s3-credentials
```

### Python (boto3) Example

```python
import boto3
import os

s3 = boto3.client(
    's3',
    endpoint_url=os.environ['AWS_ENDPOINT_URL'],
    aws_access_key_id=os.environ['AWS_ACCESS_KEY_ID'],
    aws_secret_access_key=os.environ['AWS_SECRET_ACCESS_KEY'],
    region_name=os.environ.get('AWS_REGION', 'lab-garage')
)

# List buckets
buckets = s3.list_buckets()

# Upload file
s3.upload_file('local-file.txt', 'my-bucket', 'remote-file.txt')

# Download file
s3.download_file('my-bucket', 'remote-file.txt', 'local-file.txt')
```

### Node.js (AWS SDK v3) Example

```javascript
import { S3Client, ListBucketsCommand, PutObjectCommand } from "@aws-sdk/client-s3";

const s3 = new S3Client({
  endpoint: process.env.AWS_ENDPOINT_URL,
  region: process.env.AWS_REGION || "lab-garage",
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  },
  forcePathStyle: true, // Required for Garage
});

// List buckets
const buckets = await s3.send(new ListBucketsCommand({}));

// Upload object
await s3.send(new PutObjectCommand({
  Bucket: "my-bucket",
  Key: "my-file.txt",
  Body: "Hello, World!",
}));
```

### AWS CLI Example

```bash
# Configure AWS CLI (run once)
export AWS_ACCESS_KEY_ID=<key-id>
export AWS_SECRET_ACCESS_KEY=<secret-key>
export AWS_ENDPOINT_URL=http://garage.storage.svc.cluster.local:3900
export AWS_REGION=lab-garage

# List buckets
aws s3 ls

# Upload file
aws s3 cp local-file.txt s3://my-bucket/

# Download file
aws s3 cp s3://my-bucket/file.txt ./

# Sync directory
aws s3 sync ./local-dir s3://my-bucket/remote-dir/
```

## Bucket and Key Management

Bucket and key management is done via the Garage CLI on tower-pc:

### Create Bucket

```bash
ssh tower-pc 'docker exec garage /garage bucket create my-bucket'
```

### Create Access Key

```bash
ssh tower-pc 'docker exec garage /garage key create my-app-key'
```

This outputs the key ID and secret. Save these securely.

### Grant Bucket Access

```bash
# Read and write access
ssh tower-pc 'docker exec garage /garage bucket allow my-bucket --read --write --key <KEY_ID>'

# Read-only access
ssh tower-pc 'docker exec garage /garage bucket allow my-bucket --read --key <KEY_ID>'
```

### List Buckets and Keys

```bash
ssh tower-pc 'docker exec garage /garage bucket list'
ssh tower-pc 'docker exec garage /garage key list'
```

## Network Configuration

If tower-pc IP changes:

1. Update IP in `service.yaml` Endpoints section
2. Apply: `kubectl apply -k kubernetes/base/garage`

## Monitoring

### Check Garage health

```bash
ssh tower-pc "curl -s http://127.0.0.1:3903/health"
```

### Check status

```bash
ssh tower-pc "docker exec garage /garage status"
```

### View logs

```bash
ssh tower-pc "docker logs garage"
```

### Resource usage

```bash
ssh tower-pc "systemctl status garage.slice"
```

## Troubleshooting

### Test connectivity from K8s

```bash
kubectl run s3-test --rm -it --restart=Never --image=amazon/aws-cli \
  --env="AWS_ACCESS_KEY_ID=<key>" \
  --env="AWS_SECRET_ACCESS_KEY=<secret>" \
  --env="AWS_ENDPOINT_URL=http://garage.storage.svc.cluster.local:3900" \
  -- s3 ls
```

### Common issues

1. **Connection refused**: Check Garage service is running on tower-pc
2. **Access denied**: Verify key has bucket permissions (`garage bucket info <bucket>`)
3. **Bucket not found**: Create bucket first (`garage bucket create <name>`)
4. **DNS resolution**: Ensure `storage` namespace exists and service is created
