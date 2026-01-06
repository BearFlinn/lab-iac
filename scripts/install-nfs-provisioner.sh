#!/usr/bin/env bash
#
# Install NFS Subdir External Provisioner for Kubernetes
# Uses tower-pc NFS server (10.0.0.249:/mnt/nfs-storage) for dynamic PVC provisioning
#
# Prerequisites:
#   - kubectl configured for target cluster
#   - helm installed
#   - NFS server running and accessible (tower-pc: 10.0.0.249)
#
# Usage:
#   ./install-nfs-provisioner.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../kubernetes/nfs-provisioner"
NFS_SERVER="10.0.0.249"
NFS_PATH="/mnt/nfs-storage"

echo "==> NFS Subdir External Provisioner Installation"
echo ""

# Check prerequisites
echo "==> Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "ERROR: helm not found"; exit 1; }

# Verify cluster is accessible
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "✓ kubectl configured"
echo "✓ helm found"
echo "✓ Cluster accessible"
echo ""

# Verify NFS server is accessible
echo "==> Verifying NFS server connectivity..."

# Check if showmount is available, if not try to verify via SSH
if command -v showmount >/dev/null 2>&1; then
    if showmount -e "$NFS_SERVER" >/dev/null 2>&1; then
        echo "✓ NFS server is accessible at $NFS_SERVER"
        echo ""
        echo "Available exports:"
        showmount -e "$NFS_SERVER"
        echo ""
    else
        echo "⚠️  WARNING: showmount command failed"
        echo "Attempting to verify via SSH..."
        if ssh -o ConnectTimeout=5 "$NFS_SERVER" "sudo exportfs -v" >/dev/null 2>&1; then
            echo "✓ NFS server is accessible via SSH at $NFS_SERVER"
            echo ""
        else
            echo "⚠️  WARNING: Cannot verify NFS server at $NFS_SERVER"
            echo "Make sure tower-pc is running and NFS server is configured"
            echo ""
            read -p "Continue anyway? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Installation cancelled"
                exit 1
            fi
        fi
    fi
else
    echo "ℹ️  showmount not available (nfs-common not installed)"
    echo "Verifying NFS server via SSH instead..."
    if ssh -o ConnectTimeout=5 "$NFS_SERVER" "sudo systemctl is-active nfs-server && sudo exportfs -v" >/dev/null 2>&1; then
        echo "✓ NFS server is running and configured at $NFS_SERVER"
        echo ""
    else
        echo "⚠️  WARNING: Cannot verify NFS server at $NFS_SERVER"
        echo "Make sure tower-pc is running and NFS server is configured"
        echo ""
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Installation cancelled"
            exit 1
        fi
    fi
fi

# Add Helm repository
echo "==> Adding nfs-subdir-external-provisioner Helm repository..."
if ! helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ 2>/dev/null; then
    echo "Note: Helm repo may already exist, continuing..."
fi
helm repo update

# Install or upgrade
echo "==> Installing/Upgrading nfs-subdir-external-provisioner..."
helm upgrade --install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace nfs-provisioner \
  --create-namespace \
  --values "$MANIFESTS_DIR/values.yaml" \
  --wait

echo ""
echo "==> Waiting for provisioner to be ready..."
kubectl wait --for=condition=ready pod \
  -n nfs-provisioner \
  -l app=nfs-subdir-external-provisioner \
  --timeout=120s

echo ""
echo "==> ✓ Installation complete!"
echo ""
echo "NFS Provisioner Status:"
kubectl get pods -n nfs-provisioner
echo ""
kubectl get storageclass
echo ""
echo "You can now create PersistentVolumeClaims and they will be provisioned on NFS."
echo ""
echo "Example PVC:"
echo "---"
echo "apiVersion: v1"
echo "kind: PersistentVolumeClaim"
echo "metadata:"
echo "  name: my-pvc"
echo "spec:"
echo "  accessModes:"
echo "    - ReadWriteMany"
echo "  resources:"
echo "    requests:"
echo "      storage: 10Gi"
echo "  # storageClassName: nfs-client  # Optional - will use default"
