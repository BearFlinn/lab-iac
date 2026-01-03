# Infrastructure Architecture

This document describes the bare-metal Kubernetes cluster architecture, design decisions, and implementation status.

## Overview

A development/testing Kubernetes cluster built on repurposed hardware, optimized for resource efficiency and real-world learning. The architecture prioritizes practical experience over high availability, making it ideal for portfolio demonstration and personal projects.

## Cluster Topology

```
                            Internet
                               |
                               v
                    +--------------------+
                    |    Hetzner VPS     |
                    |    (proxy-vps)     |
                    | Caddy + Cloudflare |
                    |  DNS-01 for TLS    |
                    +--------------------+
                               |
                         NetBird VPN
                               |
            +------------------+------------------+
            |                  |                  |
            v                  v                  v
+-------------------+ +-------------------+ +-------------------+
| dell-inspiron-15  | |    msi-laptop     | |     tower-pc      |
|  Control Plane    | |      Worker       | |      Worker       |
|   10.0.0.226      | |    10.0.0.XXX     | |    10.0.0.XXX     |
+-------------------+ +-------------------+ +-------------------+
                               |
                               v
                    +-------------------+
                    | dell-optiplex-9020|
                    |      Worker       |
                    |    10.0.0.XXX     |
                    +-------------------+
```

## Node Specifications

### Control Plane Node

**Dell Inspiron 15**
- **Role:** Kubernetes control plane (single-node)
- **CPU:** Intel i3-7100U (2 cores / 4 threads)
- **RAM:** 8GB
- **Storage:** 256GB SSD
- **IP Address:** 10.0.0.226
- **Resource Usage:** 2-4GB RAM, <1 CPU core for control plane components

**Control Plane Components:**
- etcd (single-node)
- kube-apiserver
- kube-controller-manager
- kube-scheduler
- CoreDNS

### Worker Nodes

#### Node 1: Monitoring & Analytics
**MSI Laptop**
- **Role:** Observability workloads
- **CPU:** Intel i7-6700HQ (4 cores / 8 threads)
- **RAM:** 32GB
- **Storage:** 2TB (SSD + HDD)
- **GPU:** NVIDIA GTX 1060 (3GB)

**Kubernetes Labels:**
```yaml
node-role.kubernetes.io/monitoring: "true"
workload: observability
gpu: nvidia-gtx-1060
storage-class: metrics
```

**Planned Workloads:**
- Prometheus + Grafana (metrics)
- Loki (log aggregation)
- Jaeger/Tempo (distributed tracing)

#### Node 2: Storage Services
**Tower PC**
- **Role:** Persistent storage and backups
- **CPU:** Intel i7-4790 (4 cores / 8 threads)
- **RAM:** 32GB
- **Storage:** 9.3TB total (NVMe + SSDs + HDDs)
- **GPU:** NVIDIA GTX 1060 (3GB)

**Kubernetes Labels:**
```yaml
node-role.kubernetes.io/storage: "true"
workload: storage
gpu: nvidia-gtx-1060
```

**Storage Architecture:**
- **Block Storage (NFS):** M.2 NVMe (128GB) as bcache + 1TB SATA SSD
- **Object Storage:** 3x2TB HDD in ZFS RAID-Z1 (~4TB usable)

#### Node 3: General Compute
**Dell Optiplex 9020**
- **Role:** Application workloads
- **CPU:** Intel i7-4790 (4 cores / 8 threads)
- **RAM:** 32GB
- **Storage:** 512GB SSD

**Kubernetes Labels:**
```yaml
node-role.kubernetes.io/compute: "true"
workload: general
```

**Workloads:**
- Application deployments
- PostgreSQL databases
- CI/CD runners
- Web services

## Total Cluster Resources

| Resource | Capacity |
|----------|----------|
| Control Plane Nodes | 1 |
| Worker Nodes | 3 |
| Total CPU | 14 cores / 28 threads |
| Total RAM | 104GB |
| GPU Nodes | 2 (MSI, Tower) |
| Total Storage | 11.5TB+ |

## Network Architecture

### IP Addressing
```
10.0.0.0/24 Network (Home LAN)
+-- 10.0.0.1       Gateway/Router
+-- 10.0.0.226     dell-inspiron-15 (Control Plane)
+-- 10.0.0.XXX     tower-pc (Storage Worker)
+-- 10.0.0.XXX     msi-laptop (Monitoring Worker)
+-- 10.0.0.XXX     dell-optiplex-9020 (Compute Worker)
```

### Kubernetes Networking

**CNI Plugin:** Calico
- Pod network CIDR: 10.244.0.0/16
- BGP mesh networking between nodes
- Network policies supported

**Service Network:** 10.96.0.0/12

### External Access

**VPS Proxy (Hetzner)**
- Caddy reverse proxy with automatic TLS
- Wildcard certificates via Cloudflare DNS-01
- NetBird VPN tunnel to home network

**Ingress (NGINX Ingress Controller)**
- HTTP NodePort: 30487
- HTTPS NodePort: 30356

## Technology Decisions

### Kubernetes Distribution
**Decision:** kubeadm

**Rationale:**
- Standard, widely-used approach
- Maximum control over cluster configuration
- Best for learning Kubernetes internals
- No vendor lock-in

### Container Runtime
**Decision:** containerd

**Rationale:**
- Kubernetes-native runtime
- Lower resource overhead than Docker
- Industry standard for production

### CNI Plugin
**Decision:** Calico

**Rationale:**
- Well-established and battle-tested
- Excellent performance
- Built-in network policy support
- Good documentation

### Storage Strategy

**Block Storage (NFS Provisioner)**
- Simple and flexible for dev/test
- High-performance tier with bcache
- Kubernetes storage class: `local-path`

**Object Storage (Garage - Planned)**
- S3-compatible API
- Backup target for Velero
- Long-term archive storage

### Node Scheduling

**Strategy:** Flexible preferences, not hard constraints

Nodes have workload preferences (monitoring, storage, compute) but allow scheduling of any workload if resources permit. This maximizes cluster utilization while respecting workload affinity when possible.

```yaml
# Example: Prefer monitoring node but allow others
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      preference:
        matchExpressions:
        - key: workload
          operator: In
          values: ["observability"]
```

## Implementation Status

### Phase 1: Base Cluster Setup [COMPLETED]
- [x] Deploy K8s control plane on Dell Inspiron 15
- [x] Join worker nodes to cluster
- [x] Configure node labels and taints
- [x] Verify cluster connectivity and health
- [x] Deploy Calico CNI with correct IP autodetection

### Phase 2: Core Infrastructure [COMPLETED]
- [x] Deploy NGINX Ingress Controller
- [x] Deploy container registry
- [x] Configure insecure registry on all nodes
- [x] Deploy GitHub Actions runners

### Phase 3: Networking & Proxy [COMPLETED]
- [x] Configure VPS proxy with Caddy
- [x] Set up NetBird VPN connectivity
- [x] Configure wildcard TLS certificates
- [x] Fix nftables rules for K8s forwarding

### Phase 4: Storage Configuration [IN PROGRESS]
- [x] Deploy local-path-provisioner
- [ ] Set up bcache on Tower PC
- [ ] Configure NFS exports for Kubernetes PVCs
- [ ] Deploy Garage for S3-compatible storage
- [ ] Configure etcd backup to NFS

### Phase 5: Observability Stack [PLANNED]
- [ ] Deploy Prometheus on MSI Laptop
- [ ] Deploy Grafana dashboards
- [ ] Set up Loki for log aggregation
- [ ] Configure retention policies

### Phase 6: GPU Support [PLANNED]
- [ ] Install NVIDIA drivers on MSI and Tower
- [ ] Deploy NVIDIA device plugin
- [ ] Test GPU scheduling

### Phase 7: Backup & Disaster Recovery [PLANNED]
- [ ] Configure etcd automated backups
- [ ] Deploy Velero for application backups
- [ ] Document and test restore procedures

## Security Considerations

### Access Control
- SSH key-based authentication only
- Kubernetes RBAC for service accounts
- GitHub runner has scoped permissions

### Network Security
- NetBird VPN for external access (zero-trust)
- UFW firewall on all nodes
- Calico network policies available

### Secrets Management
- Ansible Vault for infrastructure secrets
- Kubernetes Secrets for application credentials
- Infisical for family-dashboard (centralized secrets)

## Operational Notes

### Cluster Management

Access the cluster:
```bash
# From local machine with kubeconfig
export KUBECONFIG=~/.kube/lab-k8s-config
kubectl get nodes

# Direct SSH to control plane
ssh bearf@10.0.0.226
kubectl get nodes
```

### Backup Considerations

Currently no automated backups. Priority backups needed:
1. etcd data (cluster state)
2. PostgreSQL databases
3. Persistent volume data

### Known Limitations

1. **Single Control Plane:** No HA for control plane components
2. **Home Network:** Dependent on residential internet reliability
3. **Power:** No UPS protection documented
4. **Storage:** Local storage only, no distributed storage yet

## Future Enhancements

Short-term:
- [ ] Automated database backups
- [ ] Prometheus/Grafana monitoring
- [ ] GPU workload support

Long-term:
- [ ] HA control plane (3 nodes)
- [ ] Distributed storage (Rook/Ceph or Longhorn)
- [ ] Service mesh evaluation
- [ ] Multi-cluster federation
