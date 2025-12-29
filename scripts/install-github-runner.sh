#!/usr/bin/env bash
#
# Install GitHub Actions Runner Controller in Kubernetes
# Uses Helm for proper version control and configuration management
#
# Prerequisites:
#   - kubectl configured for target cluster
#   - helm installed
#   - cert-manager installed in cluster
#
# Usage:
#   ./install-github-runner.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../k8s-manifests/github-runner"

echo "==> GitHub Actions Runner Controller Installation"
echo ""

# Check prerequisites
echo "==> Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "ERROR: helm not found"; exit 1; }

# Check cert-manager is installed
if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
    echo "ERROR: cert-manager not installed. Install it first:"
    echo "  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml"
    exit 1
fi

echo "✓ kubectl found"
echo "✓ helm found"
echo "✓ cert-manager installed"
echo ""

# Add Helm repository
echo "==> Adding actions-runner-controller Helm repository..."
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller 2>/dev/null || true
helm repo update

# Check if values file exists
if [ ! -f "$MANIFESTS_DIR/values.yaml" ]; then
    echo "ERROR: values.yaml not found at $MANIFESTS_DIR/values.yaml"
    echo "Create it first with your GitHub PAT"
    exit 1
fi

# Install or upgrade
echo "==> Installing/Upgrading actions-runner-controller..."
helm upgrade --install actions-runner-controller \
  actions-runner-controller/actions-runner-controller \
  --namespace actions-runner-system \
  --create-namespace \
  --values "$MANIFESTS_DIR/values.yaml" \
  --wait

echo ""
echo "==> Waiting for controller to be ready..."
kubectl wait --for=condition=ready pod \
  -n actions-runner-system \
  -l app.kubernetes.io/name=actions-runner-controller \
  --timeout=180s

echo ""
echo "==> ✓ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Verify controller: kubectl get pods -n actions-runner-system"
echo "  2. Deploy runners: kubectl apply -f $MANIFESTS_DIR/runner-deployment.yaml"
echo "  3. Check runners: kubectl get runners -n actions-runner-system"
echo "  4. Verify in GitHub: https://github.com/organizations/YOUR_ORG/settings/actions/runners"
