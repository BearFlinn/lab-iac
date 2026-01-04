#!/usr/bin/env bash
# Garage S3 Installation Script
# Deploys Garage on tower-pc and configures Kubernetes access

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "==> Garage S3 Installation for lab-iac"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if [[ ! -f "$PROJECT_ROOT/.vault_pass" ]]; then
    echo "ERROR: .vault_pass file not found at $PROJECT_ROOT/.vault_pass"
    exit 1
fi

command -v ansible-playbook >/dev/null 2>&1 || {
    echo "ERROR: ansible-playbook not found. Please install Ansible."
    exit 1
}

echo "Prerequisites OK"
echo ""

# Run Ansible playbook
echo "==> Running Ansible playbook to deploy Garage..."
cd "$PROJECT_ROOT/ansible"

if ! ansible-playbook playbooks/setup-garage.yml -v; then
    echo ""
    echo "ERROR: Ansible playbook failed. Check the output above for details."
    exit 1
fi

echo ""
echo "==> Applying Kubernetes manifests..."
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

if kubectl apply -k "$PROJECT_ROOT/kubernetes/base/garage"; then
    echo "OK: Kubernetes manifests applied"
else
    echo "WARNING: Could not apply K8s manifests (may already exist)"
fi

echo ""
echo "==> Installation Complete!"
echo ""
echo "Garage S3 is now running on tower-pc (10.0.0.249:3900)"
echo ""
echo "Next steps:"
echo "  1. Create bucket: ssh tower-pc 'docker exec garage garage bucket create <name>'"
echo "  2. Create key: ssh tower-pc 'docker exec garage garage key create <name>'"
echo "  3. Allow access: ssh tower-pc 'docker exec garage garage bucket allow <bucket> --read --write --key <key-id>'"
echo ""
echo "From K8s pods, use endpoint: http://garage.storage.svc.cluster.local:3900"
