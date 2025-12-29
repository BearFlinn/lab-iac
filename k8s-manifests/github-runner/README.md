# GitHub Actions Runner Manifests

## Setup Instructions

### 1. Create values.yaml from template

```bash
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

### 5. Deploy runners

```bash
kubectl apply -f runner-deployment.yaml
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

- `values.yaml.example` - Template Helm values (copy to `values.yaml`)
- `values.yaml` - Your actual values (git-ignored, contains secrets)
- `runner-deployment.yaml` - RunnerDeployment manifest
- `README.md` - This file

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

## Scaling

Manually adjust replicas:
```bash
kubectl scale runnerdeployment lab-runners -n actions-runner-system --replicas=5
```

Or use HorizontalRunnerAutoscaler for auto-scaling based on queue length.
