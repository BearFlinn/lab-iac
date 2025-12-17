# Kubernetes Control Plane Setup Guide

This guide covers setting up the Dell Inspiron 15 as the Kubernetes control plane node for your home lab cluster.

## Prerequisites

1. **Dell Inspiron 15 must be running**:
   - Ubuntu/Debian-based OS
   - SSH access enabled
   - User `bearf` with sudo privileges
   - Static IP: 10.0.0.226

2. **From your local machine, ensure SSH key-based authentication is set up**:
   ```bash
   ssh-copy-id bearf@10.0.0.226
   ```

3. **Verify connectivity**:
   ```bash
   ansible -i ansible/inventory/control-plane.yml k8s_control_plane -m ping
   ```

## Run the Playbook

### Full automated setup:
```bash
cd /home/bearf/Projects/lab-iac
ansible-playbook -i ansible/inventory/control-plane.yml ansible/playbooks/setup-control-plane.yml
```

### With verbose output (recommended for first run):
```bash
ansible-playbook -i ansible/inventory/control-plane.yml ansible/playbooks/setup-control-plane.yml -v
```

## What the Playbook Does

### Phase 1: Prerequisites (k8s-prerequisites role)
- Loads required kernel modules (overlay, br_netfilter)
- Configures sysctl parameters for Kubernetes
- Disables swap permanently
- Installs and configures containerd runtime
- Installs CNI plugins
- Configures crictl

### Phase 2: Install Kubernetes Packages (k8s-packages role)
- Adds Kubernetes apt repository
- Installs kubeadm, kubelet, kubectl
- Holds packages at current version

### Phase 3: Initialize Control Plane (k8s-control-plane role)
- Runs `kubeadm init` with Calico pod network CIDR
- Configures kubeconfig for your user
- Installs Calico CNI plugin
- Waits for cluster to be ready
- Generates worker join command

## After Successful Setup

### Access your cluster from the Dell Inspiron:
```bash
ssh bearf@10.0.0.226
kubectl get nodes
kubectl get pods -A
```

### Or copy kubeconfig to your local machine:
```bash
scp bearf@10.0.0.226:~/.kube/config ~/.kube/lab-k8s-config
export KUBECONFIG=~/.kube/lab-k8s-config
kubectl get nodes
```

### Worker join command:
The worker node join command is saved to `/tmp/k8s-join-command.sh` on your local machine. Use this when setting up worker nodes.

## Configuration Variables

Edit `ansible/group_vars/k8s_cluster.yml` to customize:
- `kubernetes_version`: Kubernetes version (default: "1.31")
- `pod_network_cidr`: Pod network CIDR (default: "10.244.0.0/16")
- `calico_version`: Calico version (default: "v3.28.0")

## Next Steps (from ARCHITECTURE.md)

1. **Join worker nodes**:
   - MSI Laptop (10.0.0.XXX) - Monitoring workloads
   - Tower PC (10.0.0.XXX) - Storage workloads
   - Dell Optiplex (10.0.0.XXX) - General compute

2. **Configure node labels** per ARCHITECTURE.md:
   ```bash
   kubectl label node msi-laptop node-role.kubernetes.io/monitoring=true workload=observability
   kubectl label node tower-pc node-role.kubernetes.io/storage=true workload=storage
   kubectl label node dell-optiplex-9020 node-role.kubernetes.io/compute=true workload=general
   ```

3. **Phase 2: Storage Configuration** on tower-pc
4. **Phase 3: Observability Stack** on msi-laptop
5. **Phase 4: GPU Support**

## Troubleshooting

### Check containerd status:
```bash
ssh bearf@10.0.0.226 "sudo systemctl status containerd"
```

### Check kubelet logs:
```bash
ssh bearf@10.0.0.226 "sudo journalctl -u kubelet -f"
```

### Reset and start over:
```bash
ssh bearf@10.0.0.226 "sudo kubeadm reset -f && sudo rm -rf ~/.kube"
# Then re-run the playbook
```

### Verify pod CIDR:
```bash
kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}'
```

## Architecture Reference

See [ARCHITECTURE.md](../../ARCHITECTURE.md) for the complete cluster architecture and implementation phases.
