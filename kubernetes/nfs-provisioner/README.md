# NFS Provisioner Setup

Dynamic NFS-based persistent storage for Kubernetes using tower-pc NFS server.

## Overview

Uses **nfs-subdir-external-provisioner** (formerly nfs-client-provisioner) to provide automatic PersistentVolume provisioning from the tower-pc NFS server.

**NFS Server Details:**
- **Host**: 10.0.0.249 (tower-pc)
- **Export Path**: `/mnt/nfs-storage`
- **Export Network**: 10.0.0.0/24
- **Backend**: 1TB HDD with M.2 NVMe bcache acceleration

## Installation

### Method 1: Automated Script (Recommended)

```bash
cd ~/Projects/lab-iac
./scripts/install-nfs-provisioner.sh
```

### Method 2: Ansible Playbook

```bash
cd ~/Projects/lab-iac/ansible
ansible-playbook playbooks/setup-nfs-provisioner.yml
```

### Method 3: Manual Helm

```bash
cd ~/Projects/lab-iac

helm repo add nfs-subdir-external-provisioner \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/

helm install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace nfs-provisioner \
  --create-namespace \
  --values kubernetes/nfs-provisioner/values.yaml
```

## Verification

```bash
# Check provisioner pods
kubectl get pods -n nfs-provisioner

# Check StorageClass (should show as default)
kubectl get storageclass

# Test with a sample PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
EOF

# Check PVC status
kubectl get pvc test-pvc

# Verify PV was created
kubectl get pv

# Clean up test
kubectl delete pvc test-pvc
```

## Usage in Applications

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes:
    - ReadWriteMany  # NFS supports ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  # storageClassName: nfs-client  # Optional - uses default
```

## Features

- **Dynamic Provisioning**: Automatic PV creation when PVCs are created
- **ReadWriteMany**: Multiple pods can mount the same PVC
- **Archive on Delete**: PVs are renamed to `archived-*` instead of immediate deletion
- **Centralized Storage**: All data stored on tower-pc NFS server
- **Performance**: bcache acceleration via M.2 NVMe on server

## Storage Location

Created PVs are stored on the NFS server at:
```
/mnt/nfs-storage/<namespace>-<pvc-name>-<pv-name>/
```

Archived PVs are renamed to:
```
/mnt/nfs-storage/archived-<namespace>-<pvc-name>-<pv-name>/
```

## Troubleshooting

### PVC Stuck in Pending

```bash
# Check provisioner logs
kubectl logs -n nfs-provisioner -l app=nfs-subdir-external-provisioner

# Verify NFS connectivity from worker nodes
showmount -e 10.0.0.249

# Test mount manually on a worker node
sudo mount -t nfs 10.0.0.249:/mnt/nfs-storage /mnt/test
```

### Permission Issues

NFS exports are configured with `no_root_squash` on the server. If you encounter permission issues:

```bash
# On tower-pc, check NFS exports
sudo exportfs -v

# Verify export includes no_root_squash
# /mnt/nfs-storage 10.0.0.0/24(rw,sync,no_subtree_check,no_root_squash)
```

### Provisioner Not Running

```bash
# Check pod status
kubectl describe pod -n nfs-provisioner -l app=nfs-subdir-external-provisioner

# Check NFS server accessibility
ssh tower-pc
sudo systemctl status nfs-server
```

## Files

- `values.yaml` - Helm chart values (NFS server config)
- `README.md` - This file

## Integration

To include in automated cluster setup:

```yaml
# ansible/playbooks/k8s-cluster-setup.yml
- import_playbook: setup-nfs-provisioner.yml
```

## References

- [nfs-subdir-external-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner)
- [Kubernetes NFS Volumes](https://kubernetes.io/docs/concepts/storage/volumes/#nfs)
- [Dynamic NFS Provisioning](https://kubernetes.io/blog/2016/10/dynamic-provisioning-and-storage-in-kubernetes/)
