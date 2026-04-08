# ADR-017: ARC v2 for GitHub Actions Runners

**Date:** 2026-04-08
**Status:** Accepted

## Context

Phase 5 of the K8s cluster standup requires self-hosted GitHub Actions runners for the `grizzly-endeavors` org. The previous cluster used ARC v1 (summerwind `actions.summerwind.dev/v1alpha1`) with a custom DinD image, min 1 / max 4 replicas, and `PercentageRunnersBusy` autoscaling. That configuration is archived in `archive/pre-migration-2026/kubernetes/base/github-runner/`.

## Decision

Use **ARC v2** (`gha-runner-scale-set` / `gha-runner-scale-set-controller` Helm charts, OCI registry at `ghcr.io/actions/actions-runner-controller-charts`).

Key configuration choices:
- **Scale-to-zero** (`minRunners: 0`). ARC v2's event-driven autoscaling eliminates the need for a warm pool. The old setup kept min 1 because `PercentageRunnersBusy` couldn't scale to zero.
- **DinD container mode** (`containerMode.type: dind`). ARC v2 auto-injects the Docker sidecar, privileged init container, and shared volumes — no custom image needed.
- **Org-level runners** targeting `https://github.com/grizzly-endeavors`. All repos in the org can use `runs-on: [self-hosted, lab-runners]`.
- **Separate namespaces**: `arc-systems` (controller) and `arc-runners` (ephemeral runner pods), following ARC v2 conventions.
- **Deployed via Flux** as HelmReleases, matching the GitOps pattern from Phase 4.

## Alternatives Considered

- **ARC v1 (summerwind)** — The project is archived and no longer maintained. The polling-based autoscaler can't scale to zero. CRDs (`RunnerDeployment`, `HorizontalRunnerAutoscaler`) are non-standard. No reason to carry forward.
- **GitHub-hosted runners** — Not viable: workflows need access to cluster resources, lab network, and self-hosted services. Also costs money at scale.
- **Bare-metal runners (systemd)** — Loses Kubernetes scheduling, autoscaling, and isolation. Harder to observe and manage.

## Consequences

- **DinD requires privileged containers** in `arc-runners`. Runner pods have elevated privileges — acceptable since they only run org-owned workflow code, not external PRs.
- **Scale-to-zero means cold starts.** First job after idle triggers pod creation (~30-60s). Acceptable for a homelab.
- **No custom runner image initially.** Using `ghcr.io/actions/actions-runner:latest`. If workflows need Helm/kubectl/Rust pre-installed (like the old custom image), a custom image can be layered in later via `template.spec.containers[].image`.
- **Listener metrics** (`listenerMetrics`) are configured for job-level observability: started/completed counts, runner gauges, job duration histograms.
