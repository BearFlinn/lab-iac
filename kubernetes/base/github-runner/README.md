# GitHub Actions Runner Manifests

## Setup Instructions

### 1. Create values.yaml from template

```bash
cd kubernetes/github-runner
cp values.yaml.example values.yaml
```

### 2. Get GitHub Personal Access Token

1. Go to: https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Select scopes:
   - `repo` (full control)
   - For org runners: `admin:org` → `manage_runners:org`
4. Generate and copy the token

### 3. Edit values.yaml

Replace `YOUR_GITHUB_PAT_HERE` with your actual token:

```yaml
authSecret:
  github_token: "ghp_xxxxxxxxxxxxxxxxxxxx"
```

**IMPORTANT:**
- Never commit `values.yaml` with real credentials to git
- Add `values.yaml` to `.gitignore`
- Use a secrets manager (vault, sealed-secrets, etc.) for production

### 4. Run installation script

```bash
cd ~/Projects/lab-iac
./scripts/install-github-runner.sh
```

### 5. Deploy runners and autoscaler

```bash
# Using Kustomize (recommended)
kubectl apply -k kubernetes/base/github-runner

# Or apply individual files
kubectl apply -f kubernetes/base/github-runner/rbac.yaml
kubectl apply -f kubernetes/base/github-runner/docker-daemon-config.yaml
kubectl apply -f kubernetes/base/github-runner/runner-deployment.yaml
kubectl apply -f kubernetes/base/github-runner/autoscaler.yaml
```

### 6. Verify

```bash
# Check runners in Kubernetes
kubectl get runners -n actions-runner-system
kubectl get pods -n actions-runner-system

# Check in GitHub UI
# Go to: Settings → Actions → Runners
```

## Files

**Kustomize manifests (kubernetes/base/github-runner/):**
- `kustomization.yaml` - Kustomize configuration
- `runner-deployment.yaml` - RunnerDeployment manifest
- `autoscaler.yaml` - HorizontalRunnerAutoscaler for auto-scaling
- `rbac.yaml` - RBAC configuration for runner service account
- `docker-daemon-config.yaml` - Docker daemon configuration
- `README.md` - This file

**Helm values (kubernetes/github-runner/):**
- `values.yaml.example` - Template Helm values (copy to `values.yaml`)
- `values.yaml` - Your actual values (git-ignored, contains secrets)

## Usage in GitHub Actions Workflows

Target these runners using labels:

```yaml
jobs:
  build:
    runs-on: [self-hosted, kubernetes, lab]
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: echo "Running on lab K8s!"
```

## Auto-Scaling

Runners automatically scale 0-4 based on queued GitHub Actions workflow runs.

**Configuration:**
- **Min replicas:** 0 (scales to zero when idle)
- **Max replicas:** 4 (conservative cluster capacity limit)
- **Scale-down delay:** 5 minutes after scale-up
- **Metric:** Total queued and in-progress workflow runs

### Monitor Scaling

```bash
# Watch autoscaler status
kubectl get hra -n actions-runner-system -w

# Check current runner count
kubectl get runners -n actions-runner-system

# View autoscaler details and events
kubectl describe hra lab-runners-autoscaler -n actions-runner-system
```

### Manual Override (Disable Autoscaling)

To temporarily disable autoscaling:
```bash
# Delete autoscaler
kubectl delete hra lab-runners-autoscaler -n actions-runner-system

# Set manual replicas
kubectl scale runnerdeployment lab-runners -n actions-runner-system --replicas=2
```

To re-enable autoscaling:
```bash
# Re-apply autoscaler
kubectl apply -k kubernetes/base/github-runner
```
