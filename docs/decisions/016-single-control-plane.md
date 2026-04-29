# ADR-016: Single Control Plane Node

**Date:** 2026-04-05
**Status:** Accepted

## Context

The cluster has four nodes available: dell-inspiron-15 (i3-7100U, 8GB), quanta (2× Xeon E5-2670, 64GB), intel-nuc (i7-12700H, 64GB), and dell-optiplex-9020 (i7-4790, 32GB). A highly available control plane requires dedicating 3 nodes to etcd/API server, which would consume most of the cluster's capable machines for control plane duties.

## Decision

Run a single control plane node on the dell-inspiron-15. All other machines are workers.

## Alternatives Considered

- **HA control plane (3 nodes)** — Would require promoting 2 of the 3 workers to control plane roles, leaving only one dedicated worker. The stronger machines (Quanta, NUC) are far more valuable as workers than as etcd replicas.
- **Stacked control plane on workers** — Running control plane components on worker nodes alongside workloads. Adds complexity and resource contention without real HA — if etcd quorum is lost the cluster is down regardless.

## Consequences

- **All compute-heavy machines stay as workers.** Quanta (32T/64GB), NUC (20T/64GB), and Optiplex (8T/32GB) run workloads at full capacity.
- **Control plane is a SPOF.** If the Inspiron dies, the cluster is down. Existing workloads on workers keep running (pods stay up) but no new scheduling, no API access, no kubectl. Acceptable for this self-hosted environment — rebuild/reprovisioning from Ansible is the recovery path.
- **Inspiron's 8GB RAM is adequate** for a single-node control plane at this cluster size (3 workers, <100 pods). Would need revisiting if the cluster grows significantly.
