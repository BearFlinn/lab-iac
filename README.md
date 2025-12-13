# Infrastructure as Code Lab

This repository contains Infrastructure as Code (IaC) configurations for learning and experimenting with automated infrastructure deployment on Proxmox VE.

## What's Inside

This lab includes fully automated deployments using:
- **Packer**: Building Debian VM templates
- **Terraform**: Provisioning VMs on Proxmox
- **Ansible**: Configuration management and application deployment

## Projects

### 1. Kubernetes 4-Node Cluster

A production-ready, fully automated Kubernetes cluster deployment with:
- 1 control plane + 3 worker nodes
- kubeadm-based cluster with Calico CNI
- 2 CPU cores, 4GB RAM per node
- Completely automated from VM creation to cluster ready

**Quick Start:**
```bash
./deploy-k8s-cluster.sh
```

**Documentation:** [docs/K8S_CLUSTER_SETUP.md](docs/K8S_CLUSTER_SETUP.md)

### 2. Basic Web Servers (Dev Environment)

Simple 2-node web server setup for learning Terraform basics.

**Deploy:**
```bash
cd terraform/environments/dev
terraform init
terraform apply
```

## Repository Structure

```
lab-iac/
├── packer/                      # VM image building
│   ├── debian-proxmox.pkr.hcl  # Debian base template builder
│   └── http/                    # Preseed configs
│
├── terraform/
│   ├── modules/                 # Reusable Terraform modules
│   │   ├── compute/            # VM provisioning module
│   │   ├── storage/            # (Future) Storage module
│   │   └── networking/         # (Future) Networking module
│   └── environments/           # Environment-specific configs
│       ├── dev/                # Development environment
│       ├── k8s-cluster/        # Kubernetes cluster
│       ├── staging/            # (Future) Staging environment
│       └── prod/               # (Future) Production environment
│
├── ansible/
│   ├── inventory/              # Ansible inventories
│   │   └── terraform-inventory.sh  # Dynamic inventory from Terraform
│   ├── roles/                  # Ansible roles
│   │   ├── k8s-prerequisites/  # Kubernetes node preparation
│   │   ├── k8s-packages/       # Install kubeadm, kubelet, kubectl
│   │   ├── k8s-control-plane/  # Initialize control plane
│   │   └── k8s-worker/         # Join worker nodes
│   └── playbooks/              # Ansible playbooks
│       ├── k8s-cluster-setup.yml  # Kubernetes deployment
│       └── k8s-verify.yml         # Cluster verification
│
├── docs/                       # Documentation
│   ├── K8S_CLUSTER_SETUP.md   # Kubernetes cluster guide
│   ├── PROXMOX_SETUP.md       # Proxmox API setup
│   └── DEPLOYMENT_WORKFLOW.md # General workflow
│
├── deploy-k8s-cluster.sh      # One-command K8s deployment
└── destroy-k8s-cluster.sh     # One-command K8s cleanup
```

## Prerequisites

### Required Tools
- **Terraform** >= 0.13
- **Ansible** >= 2.9
- **Packer** >= 1.8
- **jq** (for dynamic inventory)
- SSH key pair at `~/.ssh/id_ed25519`

### Proxmox Setup
- Proxmox VE 7.x or 8.x
- API token configured (see [docs/PROXMOX_SETUP.md](docs/PROXMOX_SETUP.md))
- Network bridge `vmbr0` configured
- Storage pool `local-lvm` available

## Getting Started

### 1. Build Base Debian Template

```bash
cd packer
packer build debian-proxmox.pkr.hcl
```

This creates VM template ID 9000 in Proxmox.

### 2. Deploy Kubernetes Cluster

```bash
# Automated deployment
./deploy-k8s-cluster.sh

# Or manual steps:
cd terraform/environments/k8s-cluster
terraform init && terraform apply

cd ../../ansible
ansible-playbook -i inventory/terraform-inventory.sh playbooks/k8s-cluster-setup.yml
```

### 3. Access Your Cluster

```bash
# SSH to control plane
ssh debian@<control-plane-ip>
kubectl get nodes

# Or copy kubeconfig locally
scp debian@<control-plane-ip>:~/.kube/config ~/.kube/k8s-cluster-config
export KUBECONFIG=~/.kube/k8s-cluster-config
kubectl get nodes
```

## Key Features

### Fully Automated Deployment
- Zero manual steps from VM creation to working cluster
- Dynamic inventory automatically pulls VM IPs from Terraform
- Idempotent Ansible roles can be re-run safely

### Production Best Practices
- Modular Terraform code with reusable modules
- Environment separation (dev, k8s-cluster, staging, prod)
- Infrastructure as Code with version control
- Automated testing with verification playbooks

### Flexible Architecture
- Easy to add more worker nodes
- Simple to create new environments
- Extensible module system
- Well-documented and commented

## Learning Path

1. **Start with Dev Environment**: Deploy simple web servers to learn Terraform basics
2. **Build Templates with Packer**: Understand image building and automation
3. **Deploy Kubernetes**: See the full power of IaC with complex multi-node deployment
4. **Experiment**: Add monitoring, storage, ingress, etc.

## Documentation

- [Kubernetes Cluster Setup](docs/K8S_CLUSTER_SETUP.md) - Complete K8s deployment guide
- [Proxmox Setup](docs/PROXMOX_SETUP.md) - Proxmox API configuration
- [Deployment Workflow](docs/DEPLOYMENT_WORKFLOW.md) - General Packer + Terraform workflow

## Common Commands

```bash
# Deploy Kubernetes cluster
./deploy-k8s-cluster.sh

# Destroy Kubernetes cluster
./destroy-k8s-cluster.sh

# View Terraform outputs
cd terraform/environments/k8s-cluster
terraform output

# Run Ansible playbook
cd ansible
ansible-playbook -i inventory/terraform-inventory.sh playbooks/k8s-cluster-setup.yml

# Verify cluster
ansible-playbook -i inventory/terraform-inventory.sh playbooks/k8s-verify.yml
```

## Future Enhancements

- [ ] HA control plane (3 control plane nodes)
- [ ] MetalLB for LoadBalancer services
- [ ] Persistent storage (Longhorn or Rook Ceph)
- [ ] Ingress controller (nginx-ingress)
- [ ] Monitoring stack (Prometheus + Grafana)
- [ ] GitOps with ArgoCD or Flux
- [ ] CI/CD pipeline integration
- [ ] Multi-cluster federation

## Contributing

This is a personal learning lab. Feel free to fork and adapt for your own use!

## License

MIT License - Free to use for learning and experimentation.
