#!/bin/bash
# Fully automated Kubernetes cluster deployment script
# This script orchestrates Terraform and Ansible for zero-touch deployment

set -e

echo "=========================================="
echo "Kubernetes Cluster Deployment"
echo "=========================================="
echo ""

# Step 1: Deploy VMs with Terraform
echo "Step 1: Deploying VMs with Terraform..."
cd terraform/environments/k8s-cluster

if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

echo "Planning Terraform deployment..."
terraform plan

read -p "Proceed with Terraform apply? (yes/no): " terraform_confirm
if [ "$terraform_confirm" != "yes" ]; then
    echo "Deployment cancelled."
    exit 0
fi

echo "Deploying VMs..."
terraform apply -auto-approve

echo ""
echo "VMs deployed successfully!"
echo ""
echo "VM Details:"
terraform output

# Wait for SSH to be ready
echo ""
echo "Waiting for VMs to be fully ready (30 seconds)..."
sleep 30

# Step 2: Bootstrap Kubernetes with Ansible
echo ""
echo "Step 2: Bootstrapping Kubernetes cluster with Ansible..."
cd ../../../ansible

echo "Generating Ansible inventory from Terraform outputs..."
./inventory/terraform-inventory.sh --list | python3 -m json.tool > /tmp/k8s-inventory.json

echo "Running cluster setup playbook..."
ansible-playbook -i /tmp/k8s-inventory.json playbooks/k8s-cluster-setup.yml

# Step 3: Verify cluster
echo ""
echo "Step 3: Verifying cluster health..."
ansible-playbook -i /tmp/k8s-inventory.json playbooks/k8s-verify.yml

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "To access your cluster:"
echo "1. SSH to control plane: ssh debian@<control-plane-ip>"
echo "2. Or copy kubeconfig:"
echo "   scp debian@<control-plane-ip>:~/.kube/config ~/.kube/k8s-cluster-config"
echo "   export KUBECONFIG=~/.kube/k8s-cluster-config"
echo ""
echo "See docs/K8S_CLUSTER_SETUP.md for more information."
