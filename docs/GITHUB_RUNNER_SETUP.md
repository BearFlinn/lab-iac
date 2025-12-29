# GitHub Actions Runner Setup

## Overview

Deploy self-hosted GitHub Actions runners in Kubernetes using actions-runner-controller (ARC).

## Prerequisites

- ✅ Kubernetes cluster running
- ✅ cert-manager installed
- ✅ Container registry deployed
- ⚠️ GitHub Personal Access Token (PAT) required

## Installation Method

Using **Helm** for better version control and configuration management.

## Steps

### 1. Install cert-manager (if not already installed)

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml
kubectl wait --for=condition=ready pod -n cert-manager --all --timeout=180s
```

### 2. Add ARC Helm Repository

```bash
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update
```

### 3. Create GitHub PAT

Create a Personal Access Token at: https://github.com/settings/tokens

**Required scopes:**
- `repo` (full control)
- For organization runners: `admin:org` → `manage_runners:org`

Save the token securely (will be needed in next step).

### 4. Create values file

See: `k8s-manifests/github-runner/values.yaml`

### 5. Install ARC with Helm

```bash
helm install actions-runner-controller \
  actions-runner-controller/actions-runner-controller \
  --namespace actions-runner-system \
  --create-namespace \
  --values k8s-manifests/github-runner/values.yaml
```

### 6. Deploy Runner

```bash
kubectl apply -f k8s-manifests/github-runner/runner-deployment.yaml
```

### 7. Verify

```bash
# Check controller is running
kubectl get pods -n actions-runner-system

# Check runners
kubectl get runners -n actions-runner-system

# Check in GitHub UI
# Go to: https://github.com/organizations/YOUR_ORG/settings/actions/runners
```

## Troubleshooting

### Runners not appearing in GitHub

Check controller logs:
```bash
kubectl logs -n actions-runner-system deployment/actions-runner-controller-controller-manager
```

### Authentication issues

Verify secret:
```bash
kubectl get secret -n actions-runner-system controller-manager -o yaml
```

### Runner pods failing

```bash
kubectl describe runners -n actions-runner-system
kubectl logs -n actions-runner-system runner-POD-NAME
```

## Cleanup

```bash
helm uninstall actions-runner-controller -n actions-runner-system
kubectl delete namespace actions-runner-system
```
