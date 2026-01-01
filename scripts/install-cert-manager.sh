#!/usr/bin/env bash
#
# Install cert-manager for Kubernetes
# Required for: GitHub Actions runner controller, ingress controllers with TLS
#
# Prerequisites:
#   - kubectl configured for target cluster
#   - Cluster must be initialized and healthy
#
# Usage:
#   ./install-cert-manager.sh

set -euo pipefail

CERT_MANAGER_VERSION="v1.16.2"

echo "==> Installing cert-manager ${CERT_MANAGER_VERSION}"
echo ""

# Check prerequisites
echo "==> Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found"; exit 1; }

# Verify cluster is accessible
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    echo "Make sure kubectl is configured and the cluster is running"
    exit 1
fi

echo "✓ kubectl configured"
echo "✓ Cluster accessible"
echo ""

# Check if cert-manager is already installed
if kubectl get namespace cert-manager >/dev/null 2>&1; then
    echo "==> cert-manager namespace already exists"
    echo ""
    echo "Checking cert-manager pods..."
    kubectl get pods -n cert-manager
    echo ""
    echo "If cert-manager is having issues, you can reinstall by:"
    echo "  1. kubectl delete namespace cert-manager"
    echo "  2. Run this script again"
    exit 0
fi

# Install cert-manager
echo "==> Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml

echo ""
echo "==> Waiting for cert-manager to be ready..."
echo "This may take up to 2 minutes..."

# Wait for the namespace to be created
kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/cert-manager --timeout=60s

# Wait for cert-manager pods to be ready
kubectl wait --for=condition=ready pod \
  -n cert-manager \
  -l app.kubernetes.io/instance=cert-manager \
  --timeout=120s

echo ""
echo "==> ✓ Installation complete!"
echo ""
echo "cert-manager status:"
kubectl get pods -n cert-manager
echo ""
echo "cert-manager is now ready to issue certificates for your cluster."
