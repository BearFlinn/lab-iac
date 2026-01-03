#!/bin/bash
# Destroy Kubernetes cluster and VMs

set -e

echo "=========================================="
echo "Kubernetes Cluster Destruction"
echo "=========================================="
echo ""
echo "WARNING: This will destroy all VMs in the k8s-cluster environment!"
echo ""

cd terraform/environments/k8s-cluster

echo "Current VMs:"
terraform output 2>/dev/null || echo "No VMs currently deployed"
echo ""

read -p "Are you sure you want to destroy the cluster? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Destruction cancelled."
    exit 0
fi

echo ""
echo "Destroying cluster..."
terraform destroy

echo ""
echo "=========================================="
echo "Cluster destroyed successfully!"
echo "=========================================="
