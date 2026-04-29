# ADR-018: Argo Workflows as Workflow Engine

**Date:** 2026-04-08
**Status:** Accepted

## Context

Phase 5 of the K8s cluster standup requires a workflow engine for CI/CD pipelines, ETL jobs, data exports, and scheduled batch work. The cluster has ~54 cores, 100+ threads, and 216+ GB RAM across 4 nodes. The exploration doc (`docs/exploration/distributed-compute-argo-ray.md`) evaluated options and recommended Argo Workflows as the first component, with KubeRay to follow when there's data worth crunching at scale.

## Decision

Deploy **Argo Workflows** (chart v1.0.7, app v4.0.4) as the cluster workflow engine.

Key configuration choices:
- **Server enabled** with `authMode: server` (no authentication). Internal only — no external ingress until Phase 6.
- **Artifact repository**: MinIO bulk instance at `10.0.0.200:9002`, bucket `argo-artifacts`. Insecure (private LAN, no TLS). Dedicated MinIO user with scoped policy.
- **Controller metrics enabled** on port 9090 for Prometheus scraping.
- **Namespace**: `argo` (upstream default).
- **Deployed via Flux** as a HelmRelease, same pattern as ARC.

## Alternatives Considered

- **Tekton** — K8s-native but more verbose (one Pipeline + Task per step). Heavier footprint for the same work. Weaker CLI experience — Argo's `argo submit --watch` is more ergonomic for AI agent operation.
- **Custom scripts / CronJobs** — Works for simple cases but can't express DAGs, retries, conditional branching, or artifact passing. Doesn't scale to the pipeline patterns described in the exploration doc.
- **Temporal** — Powerful workflow engine but requires a persistent store (Postgres/Cassandra) and is designed for long-running stateful workflows, not batch compute. Overkill for the initial use cases.

## Consequences

- **Near-zero idle footprint.** Controller (~200MB RAM, minimal CPU) and server are the only always-on components. Workflow pods are ephemeral — they don't exist until triggered.
- **MinIO dependency.** Artifact storage requires the MinIO bulk instance on R730xd to be available. If MinIO is down, workflows can still run but can't store/retrieve artifacts.
- **No authentication.** The Argo Server API is open to anyone on the lab network. Acceptable for this self-hosted environment; would need SSO or `client` auth mode before any external exposure.
- **Composes with Ray later.** An Argo workflow step can submit a `RayJob` resource, enabling the Argo-orchestrates-Ray pattern described in the exploration doc. No changes needed to Argo's config when KubeRay is added.
- **Log archival.** `archiveLogs: true` stores container logs as artifacts in MinIO, enabling post-mortem debugging of completed workflows without relying on Loki retention.
