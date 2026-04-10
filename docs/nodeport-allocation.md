# NodePort Allocation

All K8s services exposed via NodePort, used by R730xd Prometheus for
external scraping and by the VPS ingress path (ADR-019).

Kubernetes default NodePort range: 30000-32767.

| Port  | Service                      | Purpose                          | Source File                                            |
|-------|------------------------------|----------------------------------|--------------------------------------------------------|
| 30356 | ingress-nginx HTTPS          | External HTTPS traffic via VPS   | `kubernetes/infrastructure/ingress-nginx/helmrelease.yaml` |
| 30487 | ingress-nginx HTTP           | External HTTP traffic via VPS    | `kubernetes/infrastructure/ingress-nginx/helmrelease.yaml` |
| 30500 | OCI registry                 | containerd pulls via localhost   | `kubernetes/infrastructure/registry/service.yaml`      |
| 30885 | ARC controller metrics       | Prometheus scraping              | `kubernetes/infrastructure/github-runners/metrics-service.yaml` |
| 30886 | Argo controller metrics      | Prometheus scraping              | `kubernetes/infrastructure/argo-workflows/metrics-services.yaml` |
| 30887 | Argo server metrics          | Prometheus scraping              | `kubernetes/infrastructure/argo-workflows/metrics-services.yaml` |
| 30888 | cert-manager metrics         | Prometheus scraping              | `kubernetes/infrastructure/cert-manager/metrics-service.yaml` |
| 30889 | ingress-nginx metrics        | Prometheus scraping              | `kubernetes/infrastructure/ingress-nginx/helmrelease.yaml` |

## Conventions

- **30356-30500**: Traffic-carrying services (ingress, registry)
- **30885-30889**: Metrics endpoints for Prometheus
- New allocations should pick the next available port in the appropriate range
