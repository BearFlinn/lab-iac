# Kubernetes 4-Node Cluster Setup Guide

This guide provides complete instructions for deploying a fully automated 4-node Kubernetes cluster on Proxmox using Terraform and Ansible.

## Architecture Overview

- **Cluster Type**: kubeadm-based Kubernetes
- **Topology**: 1 control plane + 3 worker nodes
- **CNI**: Calico (v3.26.1)
- **Container Runtime**: containerd
- **Resources per node**: 2 CPU cores, 4GB RAM, 30GB disk
- **OS**: Debian 13.2.0 (existing Packer template)

## Prerequisites

### Required Tools
- Terraform >= 0.13
- Ansible >= 2.9
- jq (for dynamic inventory script)
- SSH key pair configured (`~/.ssh/id_ed25519`)
- Proxmox VE server accessible at `https://10.0.0.176:8006`

### Proxmox Requirements
- VM template ID 9000 (Debian base image) must exist
- Storage pool `local-lvm` available
- Network bridge `vmbr0` configured
- API token configured for terraform user

## Deployment Workflow

The deployment is fully automated and follows these steps:

### 1. Deploy VMs with Terraform

```bash
cd terraform/environments/k8s-cluster

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy the 4 VMs
terraform apply

# Note: VMs will be created with VMIDs 200-203
# - k8s-control-1 (VMID 200)
# - k8s-worker-1 (VMID 201)
# - k8s-worker-2 (VMID 202)
# - k8s-worker-3 (VMID 203)
```

### 2. Wait for VMs to Boot and Get IPs

Terraform will automatically wait for the VMs to boot and obtain IP addresses via DHCP. The dynamic inventory script will automatically pull these IPs from Terraform output.

```bash
# View the deployed VMs and their IPs
terraform output

# View the auto-generated Ansible inventory
terraform output ansible_inventory | jq
```

### 3. Bootstrap Kubernetes Cluster with Ansible

```bash
cd ../../ansible

# Run the fully automated cluster setup
# The dynamic inventory script automatically pulls VM IPs from Terraform
ansible-playbook -i inventory/terraform-inventory.sh playbooks/k8s-cluster-setup.yml

# This playbook will:
# 1. Install containerd and configure kernel modules on all nodes
# 2. Install kubeadm, kubelet, kubectl on all nodes
# 3. Initialize the control plane with kubeadm
# 4. Install Calico CNI
# 5. Join all 3 worker nodes to the cluster
# 6. Display cluster status
```

### 4. Verify Cluster Health

```bash
# Run the verification playbook
ansible-playbook -i inventory/terraform-inventory.sh playbooks/k8s-verify.yml

# This will:
# - Verify all nodes are Ready
# - Check system pods are healthy
# - Deploy a test nginx deployment with 3 replicas
# - Verify pod scheduling across worker nodes
# - Expose nginx as a NodePort service
```

## Accessing the Cluster

### Option 1: SSH to Control Plane

```bash
# SSH to the control plane node
ssh debian@<control-plane-ip>

# Run kubectl commands
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

### Option 2: Copy kubeconfig to Local Machine

```bash
# Get the control plane IP from Terraform
cd terraform/environments/k8s-cluster
CONTROL_IP=$(terraform output -json control_plane_ips | jq -r '.["k8s-control-1"][1][0]')

# Copy the kubeconfig
scp debian@${CONTROL_IP}:~/.kube/config ~/.kube/k8s-cluster-config

# Use the config
export KUBECONFIG=~/.kube/k8s-cluster-config
kubectl get nodes
```

## Cluster Configuration

### Kubernetes Version
- **Version**: 1.28.x (latest from Debian repos)
- Packages are held at installed version to prevent unexpected upgrades
- To upgrade: `apt-mark unhold kubelet kubeadm kubectl && apt upgrade`

### Networking
- **Pod CIDR**: 192.168.0.0/16 (Calico default)
- **CNI**: Calico with IPIP encapsulation
- **Service CIDR**: 10.96.0.0/12 (kubeadm default)

### Container Runtime
- **Runtime**: containerd
- **CRI Socket**: unix:///var/run/containerd/containerd.sock
- **Cgroup Driver**: systemd (recommended for systemd-based distros)

## Common Operations

### Viewing Cluster Status

```bash
# Get node status
kubectl get nodes -o wide

# Get all pods across all namespaces
kubectl get pods -A

# Get cluster info
kubectl cluster-info

# Get Calico status
kubectl get pods -n kube-system -l k8s-app=calico-node
```

### Deploying Applications

```bash
# Create a deployment
kubectl create deployment my-app --image=nginx:latest --replicas=3

# Expose as a service
kubectl expose deployment my-app --type=NodePort --port=80

# Get service details
kubectl get svc my-app

# Access the app using any node IP and the NodePort
curl http://<any-node-ip>:<node-port>
```

### Scaling the Cluster

To add more worker nodes:

1. Update `terraform/environments/k8s-cluster/terraform.tfvars`
2. Add new VM definitions (e.g., `k8s-worker-4`)
3. Run `terraform apply`
4. Re-run the Ansible playbook to join new nodes

```bash
cd terraform/environments/k8s-cluster
# Edit terraform.tfvars to add k8s-worker-4
terraform apply

cd ../../ansible
ansible-playbook -i inventory/terraform-inventory.sh playbooks/k8s-cluster-setup.yml
```

### Troubleshooting

#### Nodes Not Ready

```bash
# Check node status
kubectl get nodes

# Describe a node to see issues
kubectl describe node <node-name>

# Check kubelet logs
ssh debian@<node-ip>
sudo journalctl -u kubelet -f
```

#### Pods Not Starting

```bash
# Check pod status
kubectl get pods -A

# Describe a pod
kubectl describe pod <pod-name> -n <namespace>

# Check pod logs
kubectl logs <pod-name> -n <namespace>
```

#### Calico Issues

```bash
# Check Calico pods
kubectl get pods -n kube-system -l k8s-app=calico-node

# Check Calico logs
kubectl logs -n kube-system -l k8s-app=calico-node

# Verify IP pools
kubectl get ippools
```

#### Re-deploying the Cluster

```bash
# Destroy the cluster
cd terraform/environments/k8s-cluster
terraform destroy

# Re-deploy
terraform apply
cd ../../ansible
ansible-playbook -i inventory/terraform-inventory.sh playbooks/k8s-cluster-setup.yml
```

## Architecture Details

### Automation Design

This setup follows production best practices for fully automated deployment:

1. **Terraform Outputs**: The Terraform configuration outputs VM details in Ansible-compatible JSON format
2. **Dynamic Inventory**: The `terraform-inventory.sh` script dynamically generates Ansible inventory from Terraform state
3. **Idempotent Roles**: All Ansible roles are idempotent and can be re-run safely
4. **No Manual Steps**: Zero manual intervention required - completely automated from VM creation to cluster ready

### File Structure

```
lab-iac/
├── terraform/environments/k8s-cluster/
│   ├── main.tf              # Terraform provider and module config
│   ├── variables.tf         # Variable definitions
│   ├── outputs.tf           # Outputs including ansible_inventory
│   └── terraform.tfvars     # VM configurations
├── ansible/
│   ├── inventory/
│   │   ├── terraform-inventory.sh  # Dynamic inventory script
│   │   └── k8s-cluster.yml         # Deprecated static inventory
│   ├── roles/
│   │   ├── k8s-prerequisites/      # Containerd, kernel modules, sysctl
│   │   ├── k8s-packages/           # Install kubeadm, kubelet, kubectl
│   │   ├── k8s-control-plane/      # Initialize control plane, install Calico
│   │   └── k8s-worker/             # Join workers to cluster
│   └── playbooks/
│       ├── k8s-cluster-setup.yml   # Main deployment playbook
│       └── k8s-verify.yml          # Cluster verification playbook
└── docs/
    └── K8S_CLUSTER_SETUP.md        # This file
```

## Next Steps / Future Enhancements

### LoadBalancer Support
Install MetalLB for LoadBalancer service type:
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
```

### Persistent Storage
Install local-path-provisioner or Longhorn for persistent volumes:
```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
```

### Ingress Controller
Install nginx-ingress for HTTP/HTTPS routing:
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
```

### Monitoring
Deploy Prometheus and Grafana for cluster monitoring:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack
```

### GitOps
Install ArgoCD or Flux for GitOps-based deployments:
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubeadm Setup Guide](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Calico Documentation](https://docs.projectcalico.org/)
- [Proxmox Terraform Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
