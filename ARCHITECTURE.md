# Infrastructure Architecture Plan

## Overview
Development/testing Kubernetes cluster optimized for resource efficiency and specialized workloads.

## Cluster Architecture

### Control Plane Node
**Dell Inspiron 15**
- **Hostname:** dell-inspiron-15
- **Role:** Kubernetes control plane (single-node)
- **Resources:** i3-7100U (2c/4t), 8GB RAM, 256GB SSD
- **Rationale:** Adequate resources for control plane components, low power consumption for always-on operation
- **Estimated Usage:** 2-4GB RAM, <1 CPU core for control plane
- **Available for Workloads:** Minimal - reserve for system components only

### Worker Nodes

#### Node 1: Monitoring & AI Analytics
**MSI Laptop**
- **Hostname:** msi-laptop
- **Primary Roles:** Observability stack, log aggregation, AI-based analytics
- **Resources:** i7-6700HQ (4c/8t), 32GB RAM, 2TB storage, NVIDIA GTX 1060 (3GB)
- **Kubernetes Labels:**
  - `node-role.kubernetes.io/monitoring=true`
  - `workload=observability`
  - `gpu=nvidia-gtx-1060`
  - `storage-class=metrics`
- **Planned Workloads:**
  - Prometheus + Grafana (metrics)
  - Loki or Elasticsearch (logs)
  - Jaeger/Tempo (traces)
  - GPU-accelerated log analysis (anomaly detection, pattern recognition)
  - Vector embeddings for log similarity
- **Storage Strategy:**
  - 1TB SSD for hot metrics/logs (recent 30 days)
  - 1TB HDD for warm storage (31-90 days)

#### Node 2: Storage & Persistent Volumes
**Tower PC**
- **Hostname:** tower-pc
- **Primary Roles:** Block storage (NFS), S3-compatible object storage, persistent volumes
- **Resources:** i7-4790 (4c/8t), 32GB RAM, 9.3TB storage (NVMe + SSDs + HDDs), NVIDIA GTX 1060 (3GB)
- **Kubernetes Labels:**
  - `node-role.kubernetes.io/storage=true`
  - `workload=storage`
  - `gpu=nvidia-gtx-1060`
- **Planned Workloads:**
  - NFS provisioner (bcache-optimized striped SSD tier)
  - Garage (S3-compatible object storage on ZFS)
  - Velero (backup/restore)
- **Storage Architecture:**
  - **Block Storage (NFS):** M.2 NVMe (128GB) as bcache + 2x1TB SATA SSD (striped/RAID0)
    - Performance: High-speed tier for hot data
    - Use case: Kubernetes PVCs, databases, ephemeral storage
  - **Object Storage (Garage/S3):** 3x2TB HDD in ZFS RAID-Z1
    - Capacity: ~4TB usable (after RAID-Z1 overhead)
    - Use case: Backups, archives, long-term storage, Velero targets

#### Node 3: General Compute
**Dell Optiplex 9020**
- **Hostname:** dell-optiplex-9020
- **Primary Roles:** Application workloads, databases, CI/CD
- **Resources:** i7-4790 (4c/8t), 32GB RAM, 512GB SSD
- **Kubernetes Labels:**
  - `node-role.kubernetes.io/compute=true`
  - `workload=general`
- **Planned Workloads:**
  - Application deployments (microservices, APIs)
  - Databases (PostgreSQL, Redis, etc.)
  - CI/CD runners (GitLab Runner, Jenkins agents)
  - Development/testing workloads
  - Web services
- **Storage Strategy:**
  - Fast SSD for application ephemeral storage and caching

## Cluster Specifications

**Total Resources:**
- Control Plane: 1 node (8GB RAM, 2c/4t)
- Workers: 3 nodes (96GB RAM, 12c/24t)
- GPU Nodes: 2 (MSI, Tower)
- Total Storage: 11.5TB+

## Implementation Phases

### Phase 1: Base Cluster Setup
- [ ] Deploy K8s control plane on Dell Inspiron 15
- [ ] Join worker nodes to cluster
- [ ] Configure node labels and taints
- [ ] Verify cluster connectivity and health

### Phase 2: Storage Configuration
- [ ] Set up bcache on Tower PC (M.2 backing 2x1TB SSD stripe)
- [ ] Configure NFS exports for Kubernetes PVCs
- [ ] Create storage classes (fast-ssd for NFS, archival-s3 for Garage)
- [ ] Deploy Garage and configure S3 endpoint
- [ ] Test persistence across node restarts
- [ ] Configure etcd backup to NFS

### Phase 3: Observability Stack
- [ ] Deploy Prometheus on MSI Laptop
- [ ] Deploy Grafana dashboards
- [ ] Set up log aggregation (Loki/Elasticsearch)
- [ ] Configure retention policies (hot/warm/cold storage)
- [ ] Optional: GPU-based log analytics

### Phase 4: GPU Support
- [ ] Install NVIDIA drivers on MSI and Tower
- [ ] Deploy NVIDIA device plugin
- [ ] Test GPU scheduling and allocation
- [ ] Deploy example GPU workload

### Phase 3b: Networking & Ingress (Critical Path for CI/CD)
- [ ] Deploy nginx Ingress Controller
- [ ] Configure ingress for CI/CD pipeline access
- [ ] Verify HTTP routing works end-to-end

### Phase 4: Backup & Disaster Recovery
- [ ] Configure etcd automated backups to NFS
- [ ] Deploy Velero for application backups
- [ ] Test restore procedures

### Phase 5: Additional Services (Future Iterations)
- [ ] MetalLB load balancer deployment
- [ ] Cert-manager for TLS (if needed for ingress)
- [ ] External DNS (optional)
- [ ] Service mesh evaluation (Istio/Linkerd if use case arises)

## Decisions Made

### Kubernetes Distribution
✅ **kubeadm** - Standard, maximum control, good for learning

### CNI Plugin
✅ **Calico** - Well-established, good performance, network policies

### Block Storage Backend
✅ **NFS provisioner** on Tower PC
- Simple and flexible for dev/test
- High-performance tier: M.2 NVMe + bcache + 2x1TB SSD stripe
- Kubernetes storage class: "fast-ssd"

### Object Storage
✅ **Garage** on Tower PC
- S3-compatible API for applications
- Backend: 3x2TB HDD in ZFS RAID-Z1 (~4TB usable)
- Kubernetes storage class: "archival-s3"
- Primary use: Velero backups, long-term archives

### Monitoring Stack
✅ **Prometheus + Grafana + Loki** - Full observability with metrics and logs

## Open Questions & Decisions Remaining

### Networking (Still TBD)
- [ ] Service mesh? (Istio, Linkerd, none for now)
- [ ] Load balancer? (MetalLB for bare-metal)
- [ ] Ingress controller? (nginx, traefik, none)

### Node Taints/Tolerations
✅ **Flexible with priority preferences**
- MSI Laptop: Prefer monitoring workloads, but allow general workloads if needed
- Tower PC: Prefer storage workloads, but allow general workloads if needed
- Implementation: Use node affinity/preferences rather than hard taints for flexibility
- Optiplex: No preferences, general purpose compute

### Networking
✅ **Phased approach, start simple**
- **Phase 1 (MVP):** nginx Ingress Controller
  - Handles CI/CD pipeline and HTTP routing
  - Easy to deploy, widely used, minimal overhead
- **Phase 2 (Future):** MetalLB load balancer
  - Provides external IP assignment for services
  - Needed for proper ingress load balancing in bare-metal
- **Phase 3 (Optional):** Service mesh (Istio/Linkerd)
  - Advanced traffic management, observability
  - Deploy only if specific use cases warrant it

### Backup Strategy
✅ **Direct NFS backups (no HA needed)**
- Control plane etcd backups: Direct to high-speed NFS ("fast-ssd" storage class)
- Application backups: Velero targets Garage S3 for cost-effective retention
- Simple approach suitable for dev/test environment

## Network Topology
```
10.0.0.0/24 Network
├── 10.0.0.XXX - tower-pc (Storage Worker)
├── 10.0.0.XXX - msi-laptop (Monitoring Worker)
├── 10.0.0.XXX - dell-optiplex-9020 (Compute Worker)
└── 10.0.0.226 - dell-inspiron-15 (Control Plane)

Note: Machines will use their current DHCP-assigned IPs, which will be
configured as static during baseline setup.
```

## Next Steps
1. Review and refine this architecture plan
2. Make decisions on open questions
3. Update Terraform/Ansible configurations to match
4. Begin Phase 1 implementation
