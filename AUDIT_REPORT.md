# Codebase Audit Report

**Audit Date:** 2026-01-05
**Target Directory:** /home/bearf/Projects/lab-iac
**Configuration:** Documentation mode (`-doc`)

---

## Executive Summary

| Metric | Value |
|--------|-------|
| **Files Analyzed** | 162 |
| **Lines of Code** | ~6,917 |
| **Critical Issues** | 14 |
| **Important Issues** | 26 |
| **Suggestions** | 12 |
| **Overall Health Score** | **68/100** |

### Top 3 Priority Areas

1. **Security** (Score: 65/100) - Hardcoded GitHub PAT, overly permissive RBAC, PostgreSQL trust authentication
2. **Test Coverage** (Score: 15/100) - No CI/CD pipeline, no Molecule tests, no automated validation
3. **Error Handling** (Score: 78/100) - Silent failures in scripts, missing backup verification

---

## Detailed Findings

### 1. Security Issues

**Category Score: 65/100**

#### Critical (Confidence 80-100)

| File:Line | Severity | Description | Confidence |
|-----------|----------|-------------|------------|
| `kubernetes/github-runner/values.yaml:8` | Critical | **Hardcoded GitHub PAT** - Personal access token committed in plain text | 95 |
| `ansible/roles/postgresql-server/templates/pg_hba.conf.j2:5` | Critical | **PostgreSQL trust authentication** - Local connections bypass authentication | 90 |
| `kubernetes/base/github-runner/rbac.yaml:28-29` | Critical | **Overly permissive RBAC** - Secrets access cluster-wide | 88 |
| `docker/github-runner/Dockerfile:9` | High | **Curl pipe to bash** - Helm installed without checksum verification | 85 |

**Recommendations:**
1. **Immediately revoke** the GitHub PAT at https://github.com/settings/tokens
2. Change PostgreSQL local auth from `trust` to `scram-sha-256`
3. Replace ClusterRole with namespace-scoped Roles for GitHub runners
4. Use package manager or verified downloads for Helm installation

#### Important (Confidence 60-79)

| File:Line | Severity | Description | Confidence |
|-----------|----------|-------------|------------|
| `kubernetes/base/github-runner/docker-daemon-config.yaml:10` | Medium | Insecure container registry (HTTP) | 78 |
| `ansible/roles/garage-server/templates/garage.toml.j2:26` | Medium | Garage admin API bound to 0.0.0.0 | 75 |
| `kubernetes/base/github-runner/rbac.yaml:37-39` | Medium | pods/exec permission cluster-wide | 75 |
| `ansible/roles/postgresql-server/defaults/main.yml:10` | Medium | PostgreSQL listening on all interfaces | 72 |
| `scripts/setup-sudoer.sh:77` | Medium | NOPASSWD sudo configuration | 68 |

#### Positive Security Patterns

- Ansible Vault used for sensitive data (`group_vars/all/vault.yml`)
- Comprehensive `.gitignore` covering secrets and sensitive files
- PostgreSQL TLS enabled by default
- Firewall rules in Ansible roles
- `no_log: true` on sensitive Ansible tasks
- Shell scripts use `set -euo pipefail`

---

### 2. Test Coverage Issues

**Category Score: 15/100**

#### Critical (Confidence 80-100)

| Area | Description | Confidence |
|------|-------------|------------|
| CI/CD Pipeline | No `.github/workflows/` directory - infrastructure changes not automatically tested | 95 |
| Molecule Tests | Zero Molecule tests across 8 Ansible roles | 90 |
| Linting | No yamllint, ansible-lint, or shellcheck configuration | 90 |
| Shell Script Tests | 12 shell scripts with complex logic have no automated tests | 85 |
| K8s Manifest Validation | 20 Kubernetes YAML files with no `--dry-run` validation | 85 |

#### Important (Confidence 60-79)

| Area | Description | Confidence |
|------|-------------|------------|
| Integration Testing | Only one verification playbook (`k8s-verify.yml`) for entire infrastructure | 75 |
| Template Testing | 9 Jinja2 templates have no render validation tests | 70 |
| Idempotency Testing | No automated verification that playbooks can run multiple times safely | 70 |
| Post-Deployment Verification | Limited verification of deployed services | 68 |

#### Positive Testing Patterns

- All 12 shell scripts use `set -euo pipefail` for error handling
- Scripts check for prerequisites before execution
- `k8s-verify.yml` demonstrates good verification practices
- Wait/retry logic in 4 scripts for race condition prevention
- 14/14 playbooks include some form of verification

**Recommended CI/CD Pipeline:**
```yaml
# Phase 1 - Quick wins
- YAML linting (yamllint)
- Shell script linting (shellcheck)
- kubectl --dry-run=client validation
- pre-commit hooks

# Phase 2 - Critical coverage
- Molecule tests for postgresql-server, garage-server
- Verification playbooks for external services

# Phase 3 - Comprehensive
- BATS tests for shell scripts
- Full stack integration tests
```

---

### 3. Error Handling Issues

**Category Score: 78/100**

#### Critical (Confidence 80-100)

| File:Line | Description | Confidence |
|-----------|-------------|------------|
| `scripts/install-ingress-nginx.sh:41` | `kubectl wait` with `\|\| true` silences deployment failures | 92 |
| `ansible/roles/postgresql-server/templates/backup-postgresql.sh.j2:24,28,35` | Database backup without integrity verification | 88 |
| `scripts/setup-kubeconfig.sh:44` | Password exposed in process list during scp | 85 |
| `ansible/roles/k8s-prerequisites/tasks/main.yml:79,83,88` | containerd config modified without validation | 84 |
| `scripts/setup-kubeconfig.sh:64,67` | kubectl downloaded without checksum verification | 82 |
| `ansible/playbooks/setup-workers.yml:53,65,77` | Node labeling with `ignore_errors` may hide cluster state issues | 81 |

#### Important (Confidence 60-79)

| File:Line | Description | Confidence |
|-----------|-------------|------------|
| `ansible/playbooks/reset-cluster.yml:26,36...` | Extensive `failed_when: false` masks real errors | 75 |
| `ansible/playbooks/k8s-verify.yml:36,48...` | Multiple `ignore_errors` in verification playbook | 74 |
| `scripts/install-nfs-provisioner.sh:54,72` | SSH timeout may be too short (5s) | 72 |
| `ansible/roles/k8s-prerequisites/tasks/main.yml:149` | crictl installation ignores errors without warning | 70 |
| `scripts/configure-insecure-registry.sh:44-53` | Complex sed without atomic operations | 68 |

#### Positive Error Handling Patterns

- 12/12 shell scripts use `set -euo pipefail`
- 18 Ansible tasks have retry logic for network operations
- Scripts validate required tools before execution
- Idempotency checks before resource creation
- Configuration validation before service restarts
- Backup before modification pattern used

---

### 4. Code Duplication Issues

**Category Score: 78/100**

#### Critical (Confidence 80-100)

| Files Involved | Description | Confidence |
|----------------|-------------|------------|
| `postgresql-server/tasks/main.yml`, `garage-server/tasks/main.yml` | Systemd service templates with docker-compose (~30 lines) | 95 |
| `postgresql-server/tasks/main.yml`, `garage-server/tasks/main.yml` | Systemd slice resource isolation (~15 lines each) | 92 |
| `setup-postgresql.yml`, `setup-garage.yml` | K8s manifest patterns (~85 lines duplicated) | 90 |
| `postgresql-server/tasks/main.yml`, `garage-server/tasks/main.yml` | Firewall rule configuration (~30 lines each) | 88 |

#### Important (Confidence 60-79)

| Files Involved | Description | Confidence |
|----------------|-------------|------------|
| `kubernetes/base/postgresql/service.yaml`, `kubernetes/base/garage/service.yaml` | Identical headless Service/Endpoints structure | 78 |
| `setup-cert-manager.yml`, `setup-nfs-provisioner.yml` | Pod wait condition pattern | 75 |
| Multiple scripts | Network CIDR ranges hardcoded (10.0.0.0/24, 10.244.0.0/16, 10.96.0.0/12) | 76 |
| Multiple install scripts | Prerequisite checking pattern (~5-10 lines each) | 72 |
| Multiple install scripts | Helm repository addition pattern | 68 |

**Recommended Refactoring:**

1. **Extract systemd service/slice management** → Create reusable role (saves ~40 lines)
2. **Centralize firewall rule configuration** → Create `firewall-rules-k8s` role (saves ~35 lines)
3. **Unify K8s Service/Endpoints creation** → Create Kustomize base or Ansible role (saves ~50 lines)
4. **Create shared shell script library** → `scripts/lib/prerequisites.sh` (saves ~25 lines)
5. **Consolidate network CIDR constants** → Move to `group_vars/k8s_cluster.yml`

#### Positive DRY Patterns

- Good role parameterization via `defaults/main.yml`
- Kubernetes manifests organized with Kustomize
- Centralized configuration in `group_vars`
- Clear separation of concerns between playbooks and roles

---

### 5. Readability Issues

**Category Score: 73/100**

#### Critical (Confidence 80-100)

| File:Line | Description | Confidence |
|-----------|-------------|------------|
| `ansible/roles/k8s-control-plane/tasks/main.yml:91-125` | Complex kubectl patch with embedded JSON | 88 |
| `ansible/roles/k8s-control-plane/tasks/main.yml:135-188` | Large shell heredoc with embedded YAML/JSON | 85 |
| `scripts/configure-insecure-registry.sh:44-53` | Complex sed commands with TOML regex | 82 |
| Multiple files | Repeated `hostvars[groups['k8s_control_plane'][0]]['k8s_join_command']` pattern | 78 |

#### Important (Confidence 60-79)

| File:Line | Description | Confidence |
|-----------|-------------|------------|
| Multiple scripts | Long lines exceeding 120 characters | 72 |
| `ansible/roles/postgresql-server/tasks/main.yml:243-311` | Complex loop with `item.0`/`item.1` product filter | 68 |
| `ansible/roles/k8s-control-plane/tasks/main.yml:67-78` | Complex regex replacements in `ansible.builtin.replace` | 66 |
| `ansible/roles/tower-storage-setup/tasks/main.yml:68-83` | ZFS property settings without explanatory comments | 62 |

#### Positive Readability Patterns

- Excellent task naming (descriptive, clear action verbs)
- Good use of handlers and `flush_handlers`
- Well-structured role organization
- Clear documentation in playbook headers
- Comprehensive shell script headers with shebang and error handling

---

### 6. Organization Issues

**Category Score: 78/100**

#### Critical (Confidence 80-100)

| Path | Description | Confidence |
|------|-------------|------------|
| `ansible/roles/*/` | Missing `meta/main.yml` files declaring role dependencies | 85 |
| `ansible/roles/k8s-packages/defaults/main.yml` | Minimal defaults without documentation | 80 |

#### Important (Confidence 60-79)

| Path | Description | Confidence |
|------|-------------|------------|
| `ansible/roles/caddy/templates/` | Two similar Caddyfile templates (`Caddyfile.j2`, `Caddyfile-k8s.j2`) | 75 |
| `ansible/inventory/` | Multiple inventory files with overlapping purposes | 70 |
| `ansible/playbooks/setup-k8s-proxy.yml` | Undefined variables not documented | 68 |
| `ansible/roles/postgresql-server/tasks/main.yml` | 337 lines - should be split into subtasks | 65 |

#### Positive Organization Patterns

- Archive clearly separated with comprehensive README
- Kubernetes manifests follow Kustomize best practices
- Roles follow standard Ansible structure
- Comprehensive documentation (CLAUDE.md, ARCHITECTURE.md, DEPLOYMENT.md, RUNBOOKS.md)
- Vault security properly implemented
- No circular dependencies detected
- Idempotent script design

---

## Metrics Summary

### Files Analyzed by Type

| Type | Count | Lines |
|------|-------|-------|
| YAML (.yml/.yaml) | 65 | ~4,650 |
| Shell scripts (.sh) | 16 | ~1,300 |
| Terraform (.tf) | 11 | ~500 |
| Jinja2 templates (.j2) | 9 | ~350 |
| HCL (.hcl) | 6 | ~120 |
| Other | 55 | - |

### Category Scores

| Category | Score | Critical | Important | Suggestions |
|----------|-------|----------|-----------|-------------|
| Security | 65/100 | 4 | 7 | 0 |
| Test Coverage | 15/100 | 5 | 4 | 3 |
| Error Handling | 78/100 | 6 | 9 | 0 |
| Duplication | 78/100 | 4 | 5 | 3 |
| Readability | 73/100 | 4 | 4 | 0 |
| Organization | 78/100 | 2 | 4 | 2 |

---

## Prioritized Action Items

### Immediate (Do Now)

1. **Revoke GitHub PAT** - The token in `kubernetes/github-runner/values.yaml` must be revoked immediately
2. **Fix PostgreSQL authentication** - Change local auth from `trust` to `scram-sha-256`
3. **Restrict RBAC permissions** - Replace ClusterRole with namespace-scoped Roles

### Short-Term (This Week)

4. **Add CI/CD pipeline** - Create GitHub Actions for linting and validation
5. **Add backup verification** - Verify backup integrity after PostgreSQL dumps
6. **Fix silent failures** - Remove `|| true` from critical kubectl wait commands
7. **Add Molecule tests** - Start with postgresql-server and garage-server roles

### Medium-Term (This Month)

8. **Extract duplicated code** - Create reusable roles for systemd services, firewall rules
9. **Add role metadata** - Create `meta/main.yml` for all Ansible roles
10. **Consolidate templates** - Merge Caddyfile templates with conditional logic
11. **Create shell library** - Extract common functions to `scripts/lib/`

### Long-Term (Backlog)

12. **Comprehensive testing** - BATS tests, idempotency tests, full stack integration
13. **Refactor large tasks** - Split postgresql-server main.yml into subtasks
14. **Documentation improvements** - Document all inventory files and variable requirements

---

## Strengths Observed

The codebase demonstrates several excellent practices:

1. **Security Discipline**: Ansible Vault usage, proper .gitignore, no_log on sensitive tasks
2. **Error Handling**: Consistent `set -euo pipefail`, retry logic, prerequisite validation
3. **Documentation**: Comprehensive CLAUDE.md, ARCHITECTURE.md, inline comments
4. **Organization**: Clear separation of concerns, Kustomize patterns, idempotent design
5. **Infrastructure Patterns**: Proper Kubernetes manifest organization, role parameterization

---

*Report generated by Claude Code audit system*
