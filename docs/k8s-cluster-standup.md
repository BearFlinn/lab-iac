# K8s Cluster Standup Plan

Phased deployment of the new K8s cluster. Each phase is self-contained — it produces a working, observable state that can be verified before moving on.

**Stack:** kubeadm, Cilium/Hubble, nginx-ingress, Flux CD, democratic-csi
**Decisions:** ADR-013 (local disk), ADR-014 (stack), ADR-015 (storage), ADR-016 (single CP)

## Nodes

| Node | Role | Specs | IP |
|------|------|-------|----|
| dell-inspiron-15 | Control plane | i3-7100U (2C/4T), 8GB | 10.0.0.226 |
| quanta | Worker | 2× Xeon E5-2670 (16C/32T), 64GB | 10.0.0.202 |
| intel-nuc | Worker | i7-12700H (14C/20T), 64GB | 10.0.0.46 |
| dell-optiplex-9020 | Worker | i7-4790 (4C/8T), 32GB | 10.0.0.187 |

---

## Phase 1: Control Plane Bootstrap

Stand up a single-node control plane on the Inspiron. No workers, no workloads — just a functioning API server with Cilium as the CNI.

**Delivers:**
- `kubeadm init` with Cilium CNI
- kubectl access from the jumpbox
- Cilium agent healthy, Hubble running
- Node in `Ready` state

**Verify before moving on:**
- `kubectl get nodes` shows Inspiron Ready
- `cilium status` reports all green
- Hubble UI or CLI can observe flows
- Control plane components healthy in `kube-system`
- Prometheus scraping kube-apiserver and etcd metrics (or exporters configured to do so)

---

## Phase 2: Workers Join

Add all three worker nodes to the cluster. Still no workloads — just a healthy multi-node cluster with networking verified between nodes.

Node-exporter and Alloy already run on all machines outside the cluster (host-level systemd), so node observability is independent of cluster health.

**Delivers:**
- containerd + kubeadm on all workers
- `kubeadm join` for Quanta, NUC, Optiplex
- Cilium networking verified cross-node

**Verify before moving on:**
- All 4 nodes Ready
- Cross-node pod communication works (deploy a test pod on each node, curl between them)
- Cilium reports healthy on all nodes
- Hubble shows cross-node flows
- Node metrics already flowing to Grafana (host-level agents, pre-existing)

---

## Phase 2.5: Cluster Metrics & Dashboards

Wire the K8s-specific metrics endpoints into the existing Prometheus/Grafana stack on R730xd. Phase 1 added apiserver + etcd scraping; this phase extends coverage to all nodes' kubelet and Cilium agents.

**Delivers:**
- Prometheus scraping kubelet (`:10250`), Cilium agent (`:9962`), Cilium operator (`:9963`) on all nodes
- K8s cluster dashboard in Grafana (node capacity, pod count, Cilium health)
- Alert rules for: node NotReady, Cilium agent down, kubelet down

**Verify before moving on:**
- Kubelet and Cilium metrics visible in Grafana
- Alerts fire when a Cilium agent is killed (test, then restore)

---

## Phase 3: Storage Provisioning

Set up democratic-csi so the cluster can dynamically provision persistent volumes from the R730xd.

**Delivers:**
- iSCSI target (targetcli) configured on R730xd
- NFS export path for dynamic provisioning on R730xd (MergerFS-backed)
- democratic-csi deployed with two StorageClasses: `iscsi-zfs` (default), `nfs-mergerfs`
- Test PVCs created and bound for both classes

**Verify before moving on:**
- `kubectl get sc` shows both StorageClasses
- A test PVC using `iscsi-zfs` provisions a zvol on the R730xd and binds
- A test PVC using `nfs-mergerfs` provisions an NFS share and binds
- A test pod can write/read data through each PVC
- Storage metrics (ZFS pool usage, NFS export health) visible in Grafana
- Alert rules for ZFS pool >80% and NFS server unreachable

---

## Phase 4: Flux CD & GitOps Foundation

Install Flux and establish the repo structure so all subsequent deployments go through git.

**Delivers:**
- Flux controllers installed (source, kustomize, helm, notification)
- Git repository source pointed at this repo
- Kustomization structure for cluster infrastructure
- Flux reconciliation working — changes in git are applied to the cluster
- Pod log collection: Alloy DaemonSet (or extended host Alloy config) tailing `/var/log/containers/*.log` and shipping to Loki with pod/namespace/container labels

**Verify before moving on:**
- `flux check` passes
- `flux get all` shows sources and kustomizations healthy
- A test change pushed to git is reconciled to the cluster automatically
- Flux notification controller configured to alert on reconciliation failures
- Flux metrics visible in Grafana (reconciliation duration, errors)
- Pod logs from Flux controllers visible in Loki (query by namespace `flux-system`)

---

## Phase 5: CI/CD — GitHub Actions Runners & Workflow Engine

Self-hosted CI/CD running in the cluster. GitHub Actions runners for repo CI, plus a workflow engine for longer-running automation and pipelines.

The old cluster used actions-runner-controller (ARC) with a custom DinD image (see `archive/pre-migration-2026/kubernetes/base/github-runner/`). The runner config can be adapted but needs proper observability this time.

**Delivers:**
- actions-runner-controller (ARC) deployed via Flux
- Runner pool for the `grizzly-endeavors` org with autoscaling
- Workflow engine deployed via Flux (Argo Workflows or CLI-native alternative — to be decided during phase planning)
- Both integrated with cluster observability

**Verify before moving on:**
- Runner pods register with GitHub and appear as available in org settings
- A test workflow dispatched from GitHub runs on a self-hosted runner and completes
- Workflow engine accessible via CLI, can submit and monitor a test workflow
- Runner metrics (active jobs, queue depth, scaling events) in Grafana
- Workflow engine metrics (execution duration, failure rate) in Grafana
- Alerts on: runner pool at zero capacity, workflow failures

---

## Phase 6: Ingress & External Access

Set up nginx-ingress, cert-manager, and wire traffic through the Hetzner VPS so external traffic can reach cluster services with automated TLS.

**Delivers:**
- cert-manager deployed via Flux (jetstack Helm chart)
- ClusterIssuer configured for Let's Encrypt (staging + production)
- nginx-ingress controller deployed via Flux
- Ingress class configured
- VPS Caddy config updated to proxy to cluster ingress
- Test service reachable from the internet with a valid TLS certificate

**Verify before moving on:**
- cert-manager pods running, `cmctl check api` passes
- ClusterIssuer ready (`kubectl get clusterissuer` shows Ready=True)
- Ingress controller pods running, external IP / NodePort assigned
- A test ingress resource routes traffic correctly inside the cluster
- A test Certificate resource is issued successfully by Let's Encrypt staging
- End-to-end: internet → VPS (Caddy) → cluster (nginx-ingress) → test service (TLS)
- Ingress metrics (request rate, latency, errors) in Grafana
- cert-manager metrics (certificate expiry, issuance failures) in Grafana
- Alerts on: ingress controller down, certificate expiry < 14 days, issuance failure

---

## Phase 7: Workload Migration

Migrate services from the staging VM to the cluster. One at a time, verify each before moving the next.

**Delivers:**
- Workloads containerized and deployed via Flux (Helm charts or Kustomize)
- PVCs provisioned for any stateful services
- DNS / VPS proxy cutover per service
- Staging VM services shut down as each migration completes

**Services to migrate (order TBD):**
- landing-page
- caz-portfolio
- resume-site
- Other services from the old cluster (Palworld, GitHub Actions runner, etc.)

**Verify before moving on:**
- Each service reachable via its production URL
- Health checks passing
- Logs in Loki, metrics in Prometheus
- Rollback plan tested (Flux can revert to previous git commit)

---

## Phase 8: Completeness — Registry, Custom Images & QoL

Polish pass across the cluster infrastructure. Everything here is deferrable — the cluster is functional without it — but rounds out the platform for day-to-day use.

**Delivers:**
- In-cluster OCI registry deployed via Flux, backed by MinIO bulk storage
- TLS for the registry via cert-manager (depends on Phase 6)
- Custom GitHub Actions runner image (Rust, Helm, Node, gh CLI, cross-compile toolchain) built automatically via Argo Workflow when the Dockerfile changes
- Runner scale set updated to use custom image from the in-cluster registry
- Argo CronWorkflow or Flux-triggered rebuild pipeline for the runner image
- Helm installed on runner image for chart-based deployments from CI
- Flux CLI upgrade (2.7.5 → latest, `flux check` flagged this)

**QoL items to audit:**
- Resource quotas / LimitRanges on workload namespaces
- Pod disruption budgets for critical controllers (Flux, ARC, Argo)
- Automatic image pull secret distribution (if registry requires auth)
- Grafana dashboard provisioning via Flux (currently copied by Ansible)
- Argo workflow default ServiceAccount set at namespace level (currently must pass `--serviceaccount` per submission)
- Consolidated NodePort allocation doc or ConfigMap (currently tracked in plan doc only)

**Verify before considering complete:**
- Custom runner image builds and pushes automatically on Dockerfile change
- A workflow using Rust/Helm/Node runs successfully on the custom image
- Registry TLS valid, containerd pulls without insecure config
- `flux check` reports no warnings
- All Grafana dashboards load without manual intervention after a fresh Grafana deploy

---

## Not Phased (Ongoing)

These happen continuously, not as a discrete phase:

- **Namespace creation** — infra namespaces by function, app projects manage their own
- **Alert tuning** — refine thresholds as real workload patterns emerge
- **Cilium network policies** — add as needed, not upfront
- **Cluster upgrades** — kubeadm upgrade process, single CP means brief API downtime
