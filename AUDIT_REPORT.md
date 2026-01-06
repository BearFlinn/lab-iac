# Codebase Audit Report

**Audit Date:** 2026-01-05
**Target Directory:** /home/bearf/Projects/lab-iac
**Configuration:** Documentation mode (`-doc`)

---

## Executive Summary

| Metric | Value |
|--------|-------|
| **Files Analyzed** | 127 files (42 infrastructure code, 31 documentation) |
| **Lines of Code** | ~7,300 lines |
| **Overall Health Score** | 65/100 |
| **Critical Issues** | 14 |
| **Important Issues** | 24 |
| **Suggestions** | 18 |

### Top 3 Priority Areas

1. **Security**: Insecure container registry, overly permissive RBAC, missing container security contexts
2. **Test Coverage**: Zero automated tests for critical infrastructure code
3. **Error Handling**: Silent failures in shell scripts and overuse of `ignore_errors` in Ansible

---

## Detailed Findings

### Critical Issues (Must Fix)

#### Security (6 issues)

| # | File | Line | Description | Confidence |
|---|------|------|-------------|------------|
| 1 | `kubernetes/base/github-runner/docker-daemon-config.yaml` | 10 | Insecure registry configured (HTTP, no TLS) - MITM attack vector | 92% |
| 2 | `scripts/configure-insecure-registry.sh` | 29-33 | Explicit TLS skip configuration for registry | 90% |
| 3 | `kubernetes/base/registry/deployment.yaml` | 16-27 | Container runs without security context (runAsNonRoot, capabilities) | 85% |
| 4 | `kubernetes/base/github-runner/rbac.yaml` | 24-67 | ClusterRole grants cluster-wide secrets access + pods/exec | 82% |
| 5 | `archive/proxmox-playground/packer/http/preseed.cfg.template` | 62 | Permanent passwordless sudo in image template | 88% |
| 6 | `archive/proxmox-playground/proxy-vps-1_cloud-init.yml` | 5 | Passwordless sudo in cloud-init | 80% |

**Recommended Fixes:**
- Enable TLS on container registry and distribute CA certificates
- Add security contexts to all Kubernetes deployments
- Replace ClusterRole with namespace-scoped Roles for GitHub runner
- Use limited sudo commands instead of NOPASSWD:ALL

#### Error Handling (8 issues)

| # | File | Line | Description | Confidence |
|---|------|------|-------------|------------|
| 1 | `scripts/setup-nfs-mount.sh` | 3 | Missing `pipefail` - piped commands fail silently | 90% |
| 2 | `scripts/setup-kubeconfig.sh` | 3 | Missing `pipefail` | 90% |
| 3 | `scripts/setup-sudoer.sh` | 3 | Missing `pipefail` | 90% |
| 4 | `scripts/setup-kubeconfig.sh` | 44 | Password in command line, stderr suppressed | 88% |
| 5 | `ansible/inventory/terraform-inventory.sh` | 16 | No error handling for missing terraform output | 87% |
| 6 | `scripts/install-ingress-nginx.sh` | 28 | Silent failure on namespace deletion (`\|\| true`) | 85% |
| 7 | `scripts/install-nfs-provisioner.sh` | 90 | Silent failure on Helm repo add | 82% |
| 8 | `scripts/install-github-runner.sh` | 41 | Silent failure on Helm repo add | 82% |

**Recommended Fixes:**
- Add `set -o pipefail` to all scripts missing it
- Remove `|| true` from Helm commands - let real failures surface
- Add explicit error messages instead of suppressing stderr

#### Test Coverage (0% - Critical Gap)

| Component | Status | Risk |
|-----------|--------|------|
| Ansible roles | No Molecule tests | Control plane failures undetected |
| Shell scripts | No BATS tests | Silent deployment failures |
| Kubernetes manifests | No kubeval/kustomize validation | Invalid YAML deployed |
| CI/CD pipeline | No GitHub Actions | No automated validation |

**Immediate Actions:**
1. Add Molecule framework for Ansible role testing
2. Add BATS framework for shell script testing
3. Add GitHub Actions CI with lint + test stages
4. Enhance `k8s-verify.yml` with network/storage tests

---

### Important Issues (Should Fix)

#### Readability (8 issues)

| # | File | Line | Description | Confidence |
|---|------|------|-------------|------------|
| 1 | `scripts/setup-sudoer.sh` | 200 | SSH command 160+ chars, unreadable | 92% |
| 2 | `ansible/roles/k8s-control-plane/tasks/main.yml` | 90-125 | 36-line undocumented Calico JSON patch | 88% |
| 3 | `scripts/configure-insecure-registry.sh` | 44 | Complex sed regex 140+ chars | 85% |
| 4 | Various playbooks | - | Missing `description:` in playbook metadata | 78% |
| 5 | Various roles | - | Jinja2 memory calculations lack inline docs | 75% |
| 6 | `ansible/playbooks/baseline-setup.yml` | - | 270-line monolithic playbook | 65% |

#### Organization (5 issues)

| # | File | Description | Confidence |
|---|------|-------------|------------|
| 1 | `kubernetes/base/kustomization.yaml` | Garage manifests NOT included - S3 service won't deploy | 95% |
| 2 | `ansible/roles/tower-storage-setup/` | Uses `vars/main.yml` instead of `defaults/main.yml` | 85% |
| 3 | `ansible/roles/garage-server/` | Missing `meta/main.yml` (all other roles have one) | 80% |
| 4 | `kubernetes/` | Confusing split between Kustomize and Helm components | 75% |
| 5 | `archive/` | 50MB of unused Terraform state/providers bloating repo | 70% |

#### Error Handling - Ansible (9 issues)

| # | File | Line | Description | Confidence |
|---|------|------|-------------|------------|
| 1 | `ansible/playbooks/k8s-verify.yml` | 36,48,57,68,80,91 | Excessive `ignore_errors` in verification playbook | 78% |
| 2 | `ansible/roles/garage-server/tasks/main.yml` | 168,202 | `failed_when: false` without clear reason | 77% |
| 3 | `ansible/playbooks/baseline-setup.yml` | 188 | Overly broad `ignore_errors` on systemd | 76% |
| 4 | `ansible/playbooks/setup-garage.yml` | 83-84 | K8s module failure handled silently | 74% |
| 5 | `scripts/fix-netbird-k8s-forwarding.sh` | 86 | nftables save without verification | 79% |

#### Duplication (4 issues)

| # | Files | Description | Lines Saved |
|---|-------|-------------|-------------|
| 1 | 4 install scripts | Repeated Helm installation pattern | ~120 lines |
| 2 | `kubernetes/base/garage/`, `postgresql/` | Identical Service/Endpoints pattern | ~70 lines |
| 3 | `install-postgresql.sh`, `install-garage.sh` | Ansible playbook wrapper boilerplate | ~40 lines |
| 4 | Multiple roles | Repeated directory creation pattern | ~25 lines |

**Recommended Refactoring:**
- Create `scripts/lib/helm-install-wrapper.sh` with common functions
- Create Kustomize component for external Service/Endpoints
- Create shared Ansible role for common directory/package operations

#### Security - Important (7 issues)

| # | File | Line | Description | Confidence |
|---|------|------|-------------|------------|
| 1 | `ansible/roles/postgresql-server/templates/pg_hba.conf.j2` | 19-22 | Non-TLS connections allowed when disabled | 75% |
| 2 | `ansible/roles/postgresql-server/templates/docker-compose.yml.j2` | 10 | Password in environment variable | 70% |
| 3 | `kubernetes/base/github-runner/rbac.yaml` | 50-52 | Cluster-wide pods/exec permission | 78% |
| 4 | `kubernetes/base/github-runner/runner-deployment.yaml` | 30 | Image from insecure registry | 75% |
| 5 | `scripts/setup-sudoer.sh` | 77 | Script enables passwordless sudo | 72% |
| 6 | `ansible/playbooks/configure-registry.yml` | 25 | Shell variable without quoting | 65% |
| 7 | `ansible/roles/k8s-prerequisites/tasks/main.yml` | 79-88 | sed commands without validation | 62% |

---

### Suggestions (Nice to Have)

#### Readability
- Standardize output styling across shell scripts (colors, prefixes)
- Add retry defaults extraction for DRY principle
- Split Calico patch into documented tasks

#### Organization
- Create `kubernetes/ORGANIZATION.md` documenting Kustomize vs Helm separation
- Add production overlay with realistic patches
- Clean up archive directory (move to separate branch)

#### Duplication
- Standardize Kubernetes namespace labels (managed-by inconsistent)
- Create parameterized `add-debian-repo` Ansible role

---

## Metrics

### Files Analyzed by Type

| Type | Count | Lines |
|------|-------|-------|
| Shell scripts | 12 | ~1,200 |
| Ansible playbooks | 14 | ~1,800 |
| Ansible roles | 28 task files | ~2,100 |
| Kubernetes manifests | 20 | ~800 |
| Terraform (archived) | 12 | ~900 |
| Documentation | 31 | ~500 |

### Category Scores

| Category | Score | Issues |
|----------|-------|--------|
| Security | 62/100 | 13 issues |
| Error Handling | 72/100 | 17 issues |
| Readability | 78/100 | 11 issues |
| Organization | 78/100 | 8 issues |
| Duplication | 72/100 | 7 issues |
| Test Coverage | 0/100 | No tests |

---

## Strengths

1. **Documentation**: Excellent `/docs/` directory with ARCHITECTURE.md, DEPLOYMENT.md, RUNBOOKS.md
2. **Naming Conventions**: Consistent snake_case variables, kebab-case files throughout
3. **Role Separation**: Clear Ansible role boundaries with appropriate scoping
4. **Secrets Management**: Proper Ansible Vault usage with gitignored vault password
5. **Idempotent Design**: Most scripts use `set -euo pipefail` correctly
6. **No Dead Code**: All scripts and playbooks are actively referenced
7. **Backup Patterns**: Good backup creation before destructive operations

---

## Recommendations

### Immediate (This Week)

1. **Fix Critical Security Issues**
   - Enable TLS on container registry
   - Add security contexts to Kubernetes deployments
   - Scope down GitHub runner RBAC

2. **Fix Critical Organization Issue**
   - Add `- garage` to `kubernetes/base/kustomization.yaml`

3. **Fix Error Handling**
   - Add `set -o pipefail` to 3 scripts
   - Remove `|| true` from Helm repo commands

### Short-term (This Month)

4. **Add Testing Framework**
   - Install Molecule for Ansible role testing
   - Install BATS for shell script testing
   - Add GitHub Actions CI pipeline

5. **Improve Error Handling**
   - Replace `ignore_errors: yes` with specific `failed_when` conditions
   - Add explicit error messages to scripts

6. **Reduce Duplication**
   - Create `scripts/lib/helm-install-wrapper.sh`
   - Create Kustomize component for external services

### Long-term (This Quarter)

7. **Enhance Test Coverage**
   - Add Molecule tests for all critical roles
   - Add BATS tests for all scripts
   - Add conformance testing with Sonobuoy

8. **Improve Readability**
   - Refactor `baseline-setup.yml` into focused playbooks
   - Document complex Jinja2 filters and JSON patches

9. **Clean Up Repository**
   - Archive or remove unused Proxmox/Terraform files
   - Implement production overlay with real configurations

---

## Audit Agents Used

| Agent | Model | Focus Area |
|-------|-------|------------|
| audit-security | opus | Vulnerabilities, secrets, RBAC |
| audit-error-handling | sonnet | Silent failures, error propagation |
| audit-test-coverage | sonnet | Test gaps, CI/CD |
| audit-readability | haiku | Naming, complexity, documentation |
| audit-organization | haiku | Structure, dead code, boundaries |
| audit-duplication | haiku | DRY violations, consolidation |

---

*Generated by Claude Code audit on 2026-01-05*
