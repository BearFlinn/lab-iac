# Documentation

## Reference

- [hardware.md](hardware.md) — machine inventory, specs, live roles
- [network.md](network.md) — topology, IPs, tunnels
- [nodeport-allocation.md](nodeport-allocation.md) — K8s NodePort registry

## Operations

- [k8s-cluster-standup.md](k8s-cluster-standup.md) — how the cluster was built, smoke tests
- [monitoring-integration.md](monitoring-integration.md) — observability stack (Prometheus, Loki, Tempo, Grafana)

## Application integration

- [residuum-feedback-plan.md](residuum-feedback-plan.md) — Residuum feedback-ingest service rollout plan
- [residuum-feedback-schema.md](residuum-feedback-schema.md) — Postgres schema for feedback ingestion

## Decisions

- [decisions/](decisions/) — Architectural Decision Records. Start here when you need to know *why* something was done.

## Exploration (not yet implemented)

- [exploration/network-vlans.md](exploration/network-vlans.md) — VLAN redesign, gated on router purchase
- [exploration/distributed-compute-argo-ray.md](exploration/distributed-compute-argo-ray.md) — Argo Workflows + Ray for distributed compute

## Hardware research

- [ap630-debian-project.md](ap630-debian-project.md) — AP630 Debian-on-aarch64 experimentation
- [aerohive-cli-reference.md](aerohive-cli-reference.md) — HiveOS CLI quick reference
- [aerohive-serial-interface.md](aerohive-serial-interface.md) — Serial access notes

## Templates

- [templates/app-deploy/](templates/app-deploy/) — Starter files for deploying a new app to the cluster

## Archive

- [../archive/](../archive/) — Pre-2026 configs (`pre-migration-2026/`), the completed 2026 migration record (`migration-2026/`), and superseded one-off projects (`proxmox-playground/`, `staging-vm/`, `migration-docs/`).
