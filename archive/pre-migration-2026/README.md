# Pre-Migration Archive

Archived: 2026-03-27

Everything in this directory was the active lab-iac configuration before the 2026 infrastructure migration. The directory structure mirrors the original repo layout.

## Why archived

The homelab is being rebuilt: new servers (R730xd, Quanta), new network (VLANs, managed switch), new storage architecture (MergerFS + SnapRAID on R730xd), and diskless PXE-booted K8s nodes. Rather than patching stale configs, the repo was reset to a clean baseline with only confirmed-current configs kept in place.

## Potentially reusable reference

These items are generic or infrastructure-agnostic and may be worth pulling back when rebuilding:

**Ansible playbooks:**
- `ansible/playbooks/k8s-verify.yml` - Generic cluster health check (deploy test nginx, check nodes/pods)
- `ansible/playbooks/reset-cluster.yml` - Generic kubeadm reset (clean CNI, iptables, kubelet dirs)
- `ansible/playbooks/setup-cert-manager.yml` - Generic cert-manager install
- `ansible/playbooks/fix-netbird-k8s.yml` - nftables rules for NetBird + K8s NodePort forwarding

**Ansible roles:**
- `ansible/roles/k8s-prerequisites/` - Kernel modules, sysctl, containerd, CNI plugin setup
- `ansible/roles/k8s-packages/` - kubeadm, kubelet, kubectl install (pinned to K8s 1.31)

**Scripts:**
- `scripts/install-cert-manager.sh` - cert-manager via kubectl apply
- `scripts/install-ingress-nginx.sh` - NGINX ingress via Helm (bare-metal NodePort config)
- `scripts/setup-kubeconfig.sh` - Copy kubeconfig from remote control plane
- `scripts/setup-sudoer.sh` - Configure passwordless sudo on a remote host

**Other:**
- `docker/github-runner/Dockerfile` - Custom GitHub Actions runner image
- `ansible/group_vars/k8s_cluster.yml` - K8s version, Calico version, pod/service CIDRs
- `kubernetes/github-runner/values.yaml` - GitHub runner Helm values (contains runner token)
