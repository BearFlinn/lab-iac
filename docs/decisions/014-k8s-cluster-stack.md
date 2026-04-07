# ADR-014: K8s Cluster Stack — kubeadm, Cilium, nginx-ingress, Flux

**Date:** 2026-04-05
**Status:** Accepted

## Context

Standing up a new K8s cluster from scratch on homelab hardware. The previous cluster ran kubeadm + Calico + nginx-ingress with ad-hoc manifest management. This time, observability is a first-class priority (Prometheus, Grafana, Loki, and Tempo already run on the R730xd), and day-to-day cluster operations will be driven primarily by an AI agent (Claude Code) working from the CLI and this IaC repo.

## Decision

- **Distribution:** kubeadm. Vanilla upstream Kubernetes — proven in the previous cluster, no bundled opinions to work around.
- **CNI:** Cilium with Hubble. eBPF-based networking with built-in network flow observability (pod-to-pod traffic, latency, drops) that integrates with the existing Grafana stack. Replaces Calico.
- **Ingress:** nginx-ingress controller. Proven, well-understood, worked well previously. TLS termination stays on the Hetzner VPS (Caddy + Cloudflare DNS-01); nginx handles routing inside the cluster.
- **GitOps:** Flux CD. Declarative YAML in-repo, CLI-driven reconciliation. Chosen over ArgoCD because Flux's CLI-first model is better suited to AI agent operation — no web UI dependency, everything observable and controllable from the terminal.
- **Namespace strategy:** Infrastructure workloads defined in this repo are organized by function (e.g., `monitoring`, `ingress`, `storage`). Application projects deployed onto the cluster manage their own namespaces.
- **Network CIDRs:** Default kubeadm ranges — `10.244.0.0/16` (pods), `10.96.0.0/12` (services). No conflict with the `10.0.0.0/24` lab subnet.

## Alternatives Considered

- **k3s** — Lighter and batteries-included, but bundles Traefik/Flannel/local-path by default. More to disable than to enable for this setup.
- **Calico (CNI)** — Worked fine previously, but lacks built-in flow observability. Would require bolting on additional tooling to match Cilium + Hubble's network visibility.
- **ArgoCD (GitOps)** — Powerful UI-driven GitOps, but heavier footprint (server, repo-server, Redis, Dex) and the UI-centric model is less useful when the primary operator works from CLI/terminal.

## Consequences

- **Cilium's eBPF model is harder to debug than iptables** when things go wrong. Acceptable tradeoff for the observability gains — `cilium status`, `hubble observe`, and Grafana dashboards cover most debugging.
- **Cilium DaemonSet uses ~256-512MB RAM per node.** Negligible on 32-64GB worker nodes.
- **Flux requires cluster state to match repo state.** All cluster changes must go through git — no `kubectl apply` side-channel. This is a feature, not a bug, for this repo's "everything is IaC" rule.
- **nginx-ingress is a known quantity.** No learning curve, no surprises.
