# Garage S3 Integration Guide

This guide covers integrating applications with the Garage S3-compatible object storage running on tower-pc.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Application Integration](#application-integration)
4. [Helm Chart Integration](#helm-chart-integration)
5. [GitHub Actions Deployment](#github-actions-deployment)
6. [Common Use Cases](#common-use-cases)
7. [Troubleshooting](#troubleshooting)

---

## Overview

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Kubernetes Cluster                                               │
│                                                                  │
│  ┌──────────────┐         ┌──────────────────────────┐         │
│  │ Application  │────────▶│ Service: garage          │         │
│  │ Pod          │   S3    │ (storage namespace)      │         │
│  └──────────────┘   API   └──────────────────────────┘         │
│                                      │                           │
└──────────────────────────────────────┼───────────────────────────┘
                                       │
                                       │ Port 3900
                                       ▼
                            ┌─────────────────────┐
                            │ tower-pc            │
                            │ 10.0.0.249:3900     │
                            │                     │
                            │ Garage v2.1.0       │
                            │ (Docker Container)  │
                            │                     │
                            │ ZFS RAID-Z1 (~4TB)  │
                            └─────────────────────┘
```

### Connection Details

| Property | Value |
|----------|-------|
| **Endpoint** | `http://garage.storage.svc.cluster.local:3900` |
| **Region** | `lab-garage` |
| **Protocol** | HTTP (internal only) |
| **Access Style** | Path-style |
| **Storage** | ~4TB usable (ZFS RAID-Z1) |

---

## Prerequisites

Before integrating your application:

1. **Garage Deployed**: Garage running on tower-pc
2. **K8s Manifests Applied**: `storage` namespace and service exist
3. **Bucket Created**: Target bucket exists in Garage
4. **Access Key Created**: Key with appropriate permissions

### Verify Prerequisites

```bash
# Check namespace and service
kubectl get svc -n storage garage

# Test connectivity from cluster
kubectl run s3-test --rm -it --restart=Never \
  --namespace=storage \
  --image=busybox \
  -- wget -qO- http://garage.storage.svc.cluster.local:3900

# Check Garage status on tower-pc
ssh tower-pc 'docker exec garage /garage status'
```

### Create Bucket and Key

```bash
# Create a bucket
ssh tower-pc 'docker exec garage /garage bucket create my-app-bucket'

# Create an access key
ssh tower-pc 'docker exec garage /garage key create my-app-key'
# Save the output - you'll need the key ID and secret

# Grant access
ssh tower-pc 'docker exec garage /garage bucket allow my-app-bucket --read --write --key <KEY_ID>'
```

---

## Application Integration

### Environment Variables

Your application should use these environment variables:

| Variable | Value |
|----------|-------|
| `AWS_ENDPOINT_URL` | `http://garage.storage.svc.cluster.local:3900` |
| `AWS_ACCESS_KEY_ID` | Your Garage key ID |
| `AWS_SECRET_ACCESS_KEY` | Your Garage secret key |
| `AWS_REGION` | `lab-garage` |
| `S3_BUCKET` | Your bucket name |

### Python (boto3)

```python
import boto3
import os

def get_s3_client():
    return boto3.client(
        's3',
        endpoint_url=os.environ['AWS_ENDPOINT_URL'],
        aws_access_key_id=os.environ['AWS_ACCESS_KEY_ID'],
        aws_secret_access_key=os.environ['AWS_SECRET_ACCESS_KEY'],
        region_name=os.environ.get('AWS_REGION', 'lab-garage')
    )

# Usage
s3 = get_s3_client()
bucket = os.environ['S3_BUCKET']

# Upload
s3.upload_fileobj(file_obj, bucket, 'path/to/object')

# Download
s3.download_file(bucket, 'path/to/object', '/local/path')

# Generate presigned URL (for downloads)
url = s3.generate_presigned_url(
    'get_object',
    Params={'Bucket': bucket, 'Key': 'path/to/object'},
    ExpiresIn=3600
)
```

### Node.js (AWS SDK v3)

```javascript
import { S3Client, PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const s3 = new S3Client({
  endpoint: process.env.AWS_ENDPOINT_URL,
  region: process.env.AWS_REGION || "lab-garage",
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  },
  forcePathStyle: true,
});

const bucket = process.env.S3_BUCKET;

// Upload
await s3.send(new PutObjectCommand({
  Bucket: bucket,
  Key: "path/to/object",
  Body: fileBuffer,
  ContentType: "application/octet-stream",
}));

// Download
const response = await s3.send(new GetObjectCommand({
  Bucket: bucket,
  Key: "path/to/object",
}));
const data = await response.Body.transformToByteArray();

// Generate presigned URL
const url = await getSignedUrl(s3, new GetObjectCommand({
  Bucket: bucket,
  Key: "path/to/object",
}), { expiresIn: 3600 });
```

### Go

```go
package main

import (
    "context"
    "os"

    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/credentials"
    "github.com/aws/aws-sdk-go-v2/service/s3"
)

func getS3Client() (*s3.Client, error) {
    cfg, err := config.LoadDefaultConfig(context.TODO(),
        config.WithRegion(os.Getenv("AWS_REGION")),
        config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(
            os.Getenv("AWS_ACCESS_KEY_ID"),
            os.Getenv("AWS_SECRET_ACCESS_KEY"),
            "",
        )),
    )
    if err != nil {
        return nil, err
    }

    return s3.NewFromConfig(cfg, func(o *s3.Options) {
        o.BaseEndpoint = aws.String(os.Getenv("AWS_ENDPOINT_URL"))
        o.UsePathStyle = true
    }), nil
}
```

---

## Helm Chart Integration

### values.yaml

```yaml
# S3 Object Storage Configuration
s3:
  endpoint: http://garage.storage.svc.cluster.local:3900
  region: lab-garage
  bucket: ""  # Override in values-{env}.yaml

  # Credentials (injected via CI/CD)
  accessKeyId: ""
  secretAccessKey: ""

image:
  repository: 10.0.0.226:32346/my-app
  tag: latest
```

### values-production.yaml

```yaml
s3:
  bucket: my-app-production

image:
  tag: v1.0.0
```

### templates/secret.yaml

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "app.fullname" . }}-s3
  labels:
    {{- include "app.labels" . | nindent 4 }}
type: Opaque
stringData:
  AWS_ENDPOINT_URL: {{ .Values.s3.endpoint | quote }}
  AWS_REGION: {{ .Values.s3.region | quote }}
  AWS_ACCESS_KEY_ID: {{ .Values.s3.accessKeyId | quote }}
  AWS_SECRET_ACCESS_KEY: {{ .Values.s3.secretAccessKey | quote }}
  S3_BUCKET: {{ .Values.s3.bucket | quote }}
```

### templates/deployment.yaml

```yaml
spec:
  template:
    spec:
      containers:
      - name: {{ .Chart.Name }}
        envFrom:
        - secretRef:
            name: {{ include "app.fullname" . }}-s3
```

---

## GitHub Actions Deployment

### Store Secrets in GitHub

Navigate to: `Settings → Secrets and variables → Actions → New repository secret`

```
S3_ACCESS_KEY_ID = GK...
S3_SECRET_ACCESS_KEY = <secret-key>
```

### Deployment Workflow

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: [self-hosted, kubernetes, lab]

    steps:
      - uses: actions/checkout@v4

      - name: Build and push image
        run: |
          docker build -t 10.0.0.226:32346/${{ github.repository }}:${{ github.sha }} .
          docker push 10.0.0.226:32346/${{ github.repository }}:${{ github.sha }}

      - name: Deploy with Helm
        run: |
          helm upgrade --install my-app ./helm \
            --namespace my-app \
            --create-namespace \
            --values ./helm/values-production.yaml \
            --set image.tag=${{ github.sha }} \
            --set s3.accessKeyId="${{ secrets.S3_ACCESS_KEY_ID }}" \
            --set s3.secretAccessKey="${{ secrets.S3_SECRET_ACCESS_KEY }}" \
            --wait
```

---

## Common Use Cases

### Application Backups

```bash
# Backup script example
#!/bin/bash
BACKUP_FILE="backup-$(date +%Y%m%d-%H%M%S).tar.gz"
tar czf /tmp/$BACKUP_FILE /data

aws s3 cp /tmp/$BACKUP_FILE s3://backups/app-name/$BACKUP_FILE \
  --endpoint-url $AWS_ENDPOINT_URL

rm /tmp/$BACKUP_FILE
```

### Media/Asset Storage

Store user uploads, images, or static assets:

```python
def upload_user_file(user_id: str, file_obj, filename: str) -> str:
    key = f"uploads/{user_id}/{filename}"
    s3.upload_fileobj(file_obj, bucket, key)
    return key

def get_file_url(key: str) -> str:
    return s3.generate_presigned_url(
        'get_object',
        Params={'Bucket': bucket, 'Key': key},
        ExpiresIn=3600
    )
```

### Log Archival

Archive old logs to S3:

```bash
# Compress and upload logs older than 7 days
find /var/log/app -name "*.log" -mtime +7 | while read f; do
  gzip "$f"
  aws s3 mv "${f}.gz" s3://logs/archived/ --endpoint-url $AWS_ENDPOINT_URL
done
```

---

## Troubleshooting

### Connection Refused

**Symptom:** Application cannot connect to S3 endpoint

**Debug:**
```bash
# Test from pod
kubectl exec -it deployment/my-app -- curl http://garage.storage.svc.cluster.local:3900

# Check service exists
kubectl get svc -n storage garage

# Check Garage is running
ssh tower-pc 'docker exec garage /garage status'
```

### Access Denied

**Symptom:** `AccessDenied` or `403` errors

**Debug:**
```bash
# Check key has bucket access
ssh tower-pc 'docker exec garage /garage bucket info my-bucket'

# Verify key ID matches
ssh tower-pc 'docker exec garage /garage key info <KEY_ID>'

# Grant access if missing
ssh tower-pc 'docker exec garage /garage bucket allow my-bucket --read --write --key <KEY_ID>'
```

### Bucket Not Found

**Symptom:** `NoSuchBucket` error

**Debug:**
```bash
# List all buckets
ssh tower-pc 'docker exec garage /garage bucket list'

# Create if missing
ssh tower-pc 'docker exec garage /garage bucket create my-bucket'
```

### Signature Mismatch

**Symptom:** `SignatureDoesNotMatch` error

**Causes:**
1. Wrong secret key
2. Clock skew between client and server
3. Incorrect endpoint URL

**Fixes:**
```bash
# Verify credentials
kubectl get secret my-app-s3 -o yaml

# Check time sync
kubectl exec -it deployment/my-app -- date
ssh tower-pc date
```

### Terraform S3 Backend Compatibility Issues

**Symptom:** `AuthorizationHeaderMalformed: Authorization header malformed, unexpected scope: YYYYMMDD/region/s3/aws4_request`

**Affected Versions:**
- Garage v2.1.0
- Terraform >= 1.6.0 with S3 backend

**Root Cause:**
Garage v2.1.0 has strict AWS Signature Version 4 scope validation that doesn't accept the scope format sent by Terraform's S3 backend. Terraform sends scope strings like `20260104/us-east-1/s3/aws4_request` which Garage rejects as malformed.

**Known Issues:**
- Terraform `backend "s3"` fails during `terraform init` with scope validation errors
- Affects all Terraform configurations using S3 backend with Garage
- Issue persists regardless of region configuration or endpoint settings
- Using `skip_credentials_validation`, `use_path_style`, and other compatibility flags doesn't resolve the issue

**Workarounds:**

1. **Use PostgreSQL Backend (Recommended for Terraform state)**
   ```hcl
   terraform {
     backend "pg" {
       conn_str    = "postgres://user:pass@host:port/dbname"
       schema_name = "terraform_remote_state"
     }
   }
   ```

   Benefits:
   - Native state locking
   - No signature compatibility issues
   - Works with existing PostgreSQL infrastructure

2. **Use HTTP Backend**
   ```hcl
   terraform {
     backend "http" {
       address = "https://your-state-server.example.com/terraform.tfstate"
     }
   }
   ```

   Note: Requires separate HTTP state storage service

3. **Upgrade Garage (To Be Tested)**
   - Garage versions >= 0.9.x may have improved AWS SDK compatibility
   - Test with newer Garage versions when upgrading
   - Check Garage changelog for AWS Signature V4 fixes

**Application Code (boto3, AWS SDKs):**
- Most AWS SDK libraries work fine with Garage v2.1.0
- Only Terraform's S3 backend is affected
- Standard S3 operations (GetObject, PutObject, ListBuckets) work normally

**Future Investigation:**
- [ ] Test Terraform S3 backend with Garage v0.9.x or later
- [ ] Check if Garage configuration options can relax signature validation
- [ ] Investigate if Terraform can use AWS Signature V2 instead of V4
- [ ] Consider contributing fix to Garage or Terraform upstream

**Reference:**
- Issue discovered: 2026-01-04
- Project: game-server-platform
- Context: Attempting to use Terraform S3 backend for port-assignments state

---

## Security Best Practices

1. **Separate Keys Per Application**: Create unique access keys for each app
2. **Least Privilege**: Only grant read or write as needed
3. **Rotate Keys**: Periodically create new keys and update secrets
4. **Don't Commit Keys**: Store in GitHub Secrets or Infisical

### Create Read-Only Key for Analytics

```bash
# Create key
ssh tower-pc 'docker exec garage /garage key create analytics-key'

# Grant read-only access
ssh tower-pc 'docker exec garage /garage bucket allow my-bucket --read --key <KEY_ID>'
```

---

## Additional Resources

- [Garage Documentation](https://garagehq.deuxfleurs.fr/documentation/)
- [AWS SDK for Python (boto3)](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html)
- [AWS SDK for JavaScript v3](https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/)
- [S3 API Reference](https://docs.aws.amazon.com/AmazonS3/latest/API/Welcome.html)

---

**Last Updated**: 2026-01-03
**Garage Version**: v2.1.0
**Storage Capacity**: ~4TB (ZFS RAID-Z1)
