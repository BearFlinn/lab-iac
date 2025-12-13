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

echo "Proceeding with Terraform apply..."
terraform apply -auto-approve

echo ""
echo "VMs deployed successfully!"
echo ""
echo "VM Details:"
terraform output

# Wait for IPs to be assigned
echo ""
echo "Waiting for VMs to receive IP addresses..."
MAX_RETRIES=30
RETRY_DELAY=10

retry_count=0
while [ $retry_count -lt $MAX_RETRIES ]; do
    # Refresh terraform state to get latest VM info including IPs
    terraform refresh > /dev/null 2>&1 || true

    # Get the ansible inventory and check if it has any hosts
    INVENTORY=$(terraform output -json ansible_inventory | jq -r '.' | python3 -m json.tool 2>/dev/null)

    # Count the number of hosts in the inventory with valid (non-link-local) IP addresses
    HOST_COUNT=$(echo "$INVENTORY" | python3 -c "
import sys, json, ipaddress
data = json.load(sys.stdin)
valid_hosts = 0
cp = data.get('all', {}).get('children', {}).get('k8s_cluster', {}).get('children', {}).get('k8s_control_plane', {}).get('hosts', {})
w = data.get('all', {}).get('children', {}).get('k8s_cluster', {}).get('children', {}).get('k8s_workers', {}).get('hosts', {})
for host_dict in list(cp.values()) + list(w.values()):
    ip = host_dict.get('ansible_host', '')
    try:
        ip_obj = ipaddress.ip_address(ip)
        # Skip link-local addresses (169.254.x.x)
        if not ip_obj.is_link_local:
            valid_hosts += 1
    except:
        pass
print(valid_hosts)
" 2>/dev/null || echo "0")

    if [ "$HOST_COUNT" -ge 4 ]; then
        echo "All 4 VMs have IP addresses assigned!"
        break
    fi

    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $MAX_RETRIES ]; then
        echo "  Waiting for IP assignment... (Attempt $retry_count/$MAX_RETRIES) - Found $HOST_COUNT/4 VMs"
        sleep $RETRY_DELAY
    fi
done

if [ "$HOST_COUNT" -lt 4 ]; then
    echo "ERROR: Not all VMs received IP addresses after $(($MAX_RETRIES * $RETRY_DELAY)) seconds"
    echo "Found only $HOST_COUNT/4 VMs with IPs"
    exit 1
fi

# Step 2: Bootstrap Kubernetes with Ansible
echo ""
echo "Step 2: Bootstrapping Kubernetes cluster with Ansible..."
cd ../../../ansible

echo "Generating Ansible inventory from Terraform outputs..."
cd ../terraform/environments/k8s-cluster
terraform output -json ansible_inventory | jq -r '.' > /tmp/k8s-inventory.json
cd ../../../ansible

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
