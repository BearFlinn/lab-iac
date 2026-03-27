#!/usr/bin/env bash
# PostgreSQL Installation Script
# Deploys PostgreSQL on tower-pc and configures Kubernetes access

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "==> PostgreSQL Installation for lab-iac"
echo ""

# Check prerequisites
echo "Checking prerequisites..."
command -v ansible-playbook >/dev/null 2>&1 || {
    echo "ERROR: ansible-playbook not found. Please install Ansible."
    exit 1
}

command -v kubectl >/dev/null 2>&1 || {
    echo "ERROR: kubectl not found. Please install kubectl."
    exit 1
}

# Check kubectl connectivity
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to Kubernetes cluster. Check your kubeconfig."
    exit 1
fi

echo "Prerequisites OK"
echo ""

# Run Ansible playbook
echo "==> Running Ansible playbook to deploy PostgreSQL..."
cd "$PROJECT_ROOT/ansible"

if ! ansible-playbook playbooks/setup-postgresql.yml; then
    echo ""
    echo "ERROR: Ansible playbook failed. Check the output above for details."
    exit 1
fi

echo ""
echo "==> Testing PostgreSQL connectivity..."

# Test direct connection to tower-pc
echo "Testing direct connection to tower-pc..."
if ssh tower-pc "docker exec postgresql pg_isready -U postgres" >/dev/null 2>&1; then
    echo "✓ Direct connection to tower-pc PostgreSQL: OK"
else
    echo "✗ Direct connection failed (this may be expected if firewall is strict)"
fi

# Test from Kubernetes
echo "Testing connectivity from Kubernetes cluster..."
if kubectl run pg-test --rm -i --restart=Never \
    --image=postgres:16-alpine \
    --namespace=database \
    -- sh -c "pg_isready -h postgresql.database.svc.cluster.local -p 5432" 2>/dev/null; then
    echo "✓ Kubernetes connectivity: OK"
else
    echo "✗ Kubernetes connectivity test failed"
    echo "  This may be due to pending service creation. Wait a moment and try:"
    echo "  kubectl run pg-test --rm -it --restart=Never --image=postgres:16-alpine --namespace=database -- pg_isready -h postgresql.database.svc.cluster.local"
fi

echo ""
echo "==> Installation Complete!"
echo ""
echo "PostgreSQL is now running on tower-pc (10.0.0.249)"
echo ""
echo "Next steps:"
echo "  1. Create databases and users as needed"
echo "  2. Create Kubernetes secrets for your applications"
echo "  3. Update applications to use: postgresql.database.svc.cluster.local:5432"
echo ""
echo "See kubernetes/base/postgresql/README.md for detailed usage instructions."
