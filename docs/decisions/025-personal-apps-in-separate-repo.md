# ADR-025: Personal App Deployments in a Separate `lab-apps` Repo

**Date:** 2026-04-18
**Status:** Accepted

## Context

ADR-020 established the app delivery model for *first-party* apps — projects where a repo owns both source code and a `deploy/` Helm chart, onboarded to grizzly-platform via the `register-app.yaml` reusable workflow. That pattern assumes every app has a repo of its own with code in it.

Personal self-hosted services (Obsidian LiveSync/CouchDB, Immich, Nextcloud, etc.) don't fit that shape: there is no source code to own, only manifests wrapping upstream Helm charts or container images. Shoe-horning each into its own repo under `grizzly-endeavors` would produce N repos that contain nothing but a `deploy/` directory, and the `register-app.yaml` workflow — which verifies the caller has a `deploy/` dir and opens a grizzly-platform PR per app — is overkill for what is effectively a folder of static YAML.

The remaining options are: (a) drop personal-app manifests into `grizzly-platform/kubernetes/apps/` alongside first-party apps, or (b) a single separate repo that holds manifests for all personal apps, wired to Flux the same way an app repo would be.

## Decision

**Personal self-hosted apps live in a new repo, `grizzly-endeavors/lab-apps`.** Layout is `apps/<name>/` per service, each folder containing the Flux/Kubernetes manifests needed to stand the app up (namespace, `HelmRepository` or `GitRepository`, `HelmRelease`, `ExternalSecret`, `Ingress`). `apps/kustomization.yaml` lists the enabled apps.

**grizzly-platform registers the repo once** via `kubernetes/clusters/grizzly-platform/personal-apps.yaml` — a `GitRepository` + top-level `Kustomization` pointing at `./apps` in lab-apps. After that, adding a new personal app is one PR in lab-apps (new folder + one line in `apps/kustomization.yaml`). grizzly-platform is not touched.

**Conventions inherit from the platform:**
- PVCs default to the `nfs-mergerfs` storage class (democratic-csi on R730xd) per ADR-015.
- Secrets use `ExternalSecret` → `ClusterSecretStore/openbao` with paths under `secret/lab-apps/<app>/<name>` — parallel to the `grizzly-platform/` prefix used for platform secrets in ADR-024.
- External TLS stays terminated at the Hetzner VPS Caddy (ADR-019); in-cluster ingress is plain HTTP on subdomains covered by the existing wildcard.

## Alternatives Considered

- **Put personal-app manifests directly in `grizzly-platform/kubernetes/apps/`.** Simpler — one repo, no new Flux source — but conflates two different delivery models: first-party apps onboarded via the `register-app.yaml` workflow (which expects a `deploy/` dir in the calling repo) vs. static manifests for upstream charts. Would also require either bypassing or extending the onboarding workflow for the upstream-chart case, muddying the ADR-020 invariant that "each app repo owns its manifests." **Rejected** because the two domains have different change cadence, blast radius, and reviewers (platform vs. consumer services), and separation is cheap.
- **One repo per personal app under `grizzly-endeavors`.** Matches the ADR-020 shape exactly but produces many content-free repos just to satisfy the onboarding workflow. The workflow's value is automating the grizzly-platform-side registration, which here is a one-time cost that's already paid the moment `personal-apps.yaml` is merged. **Rejected** as ceremony without benefit.
- **Upstream chart forks under `grizzly-endeavors`.** Gives full control over values and history but inherits maintenance burden for every upstream release. **Rejected** — pinning a chart version in `HelmRelease.spec.chart.spec.version` against the upstream `HelmRepository` gives the same reproducibility without the fork.

## Consequences

- **Personal apps deploy independently of platform changes.** A bad CouchDB values tweak can't block infrastructure reconciliation, and vice versa. The top-level `personal-apps` Kustomization has `wait: false` so a single broken app doesn't pin the parent unready.
- **Two repos to clone for full cluster reconstruction.** `flux bootstrap` reads grizzly-platform, which references lab-apps as a `GitRepository`; disaster recovery is still one command, but the audit story now spans two git histories.
- **OpenBao path layout grows a sibling prefix.** `secret/lab-apps/...` sits next to `secret/grizzly-platform/...`. The `eso-platform-read` policy must grant read on both prefixes, or a new `eso-apps-read` policy is added — revisit once there's more than one app to see which is cleaner.
- **The `register-app.yaml` workflow does not apply here.** Onboarding a new personal app is a hand-written PR in lab-apps. Low friction given the cadence (single-digit apps/year expected), but if it grows, a mirror workflow template in lab-apps is additive.
- **`prune: true` on the personal-apps Kustomization** means removing an app folder from lab-apps deletes its in-cluster resources — including PVCs unless retained by storage class policy. Document per-app backup expectations in the app's own README.

## References

- ADR-020 (app delivery via per-repo Flux sources) — the model this ADR complements for a different class of workload.
- ADR-014 (K8s cluster stack) — establishes Flux as the GitOps engine.
- ADR-015 (dynamic storage provisioning) — source of the `nfs-mergerfs` storage class.
- ADR-019 (ingress and TLS termination) — why in-cluster ingress is plain HTTP.
- ADR-024 (platform secrets on OpenBao) — path-layout convention extended here under `lab-apps/`.
- `kubernetes/clusters/grizzly-platform/personal-apps.yaml` — the registration point.
- `grizzly-endeavors/lab-apps` — the new repo.
