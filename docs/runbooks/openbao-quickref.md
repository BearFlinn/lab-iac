# OpenBao Quick Reference

First-stop pointer for "where do I find / do X with OpenBao?" Everything else lives in the linked files.

## At a glance

| | |
|---|---|
| Host | `r730xd` (`10.0.0.200`) |
| API | `https://10.0.0.200:8200` |
| CA cert | `/etc/openbao/tls/ca.crt` on r730xd (also in system trust store) |
| Version | OpenBao 2.5.x (see `ansible/roles/r730xd-openbao/defaults/main.yml`) |
| Storage | Integrated Raft at `/mnt/zfs/foundation/openbao/data` |
| Backup | Daily Raft snapshot @ 02:15 → `/mnt/zfs/foundation/openbao/backup/` |
| Seal | Shamir 5-of-3; keys live in Infisical + auto-fetched at boot |
| LAN-only | No public exposure; see ADR-019 + ADR-023 |

## File + tool locations

| Thing | Where |
|---|---|
| Role | `ansible/roles/r730xd-openbao/` |
| Deploy playbook | `ansible/playbooks/deploy-openbao.yml` |
| Bootstrap (one-time init) | `ansible/playbooks/bootstrap-openbao.yml` |
| Rotation (rekey / root / infisical-id) | `ansible/playbooks/rotate-openbao-keys.yml` |
| Vault secrets helper | `scripts/set-openbao-bootstrap-secrets.sh` |
| ADR | `docs/decisions/023-self-hosted-openbao-on-r730xd.md` |
| Rotation runbook | `docs/runbooks/openbao-rotation.md` |
| DR runbook | `docs/runbooks/openbao-disaster-recovery.md` |
| Prometheus target | `ansible/roles/r730xd-prometheus/templates/targets.d/openbao.yml.j2` |
| Prometheus alerts | `rules/homelab.yml.j2` → `openbao` group |

## Infisical bootstrap project

- **Workspace / project ID:** `.infisical.json` at repo root (`workspaceId` field). Also lives in `vars.yml` as `openbao_infisical_project_id` via a `lookup('file', $PWD + '/.infisical.json')`.
- **Environment slug:** `prod` (default `openbao_infisical_env`)
- **Secret names:**
  - `OPENBAO_UNSEAL_KEY_1` .. `OPENBAO_UNSEAL_KEY_5`
  - `OPENBAO_ROOT_TOKEN`
  - All stored as **`shared`** (not `personal`) — important, since the universal-auth machine identity on r730xd reads shared secrets.
- **Machine identity:** universal-auth; client_id + client_secret stored in Ansible vault as `vault_infisical_openbao_client_id` / `_client_secret`, templated into `/etc/openbao/infisical-auth.env` (0600 root) on r730xd.

## Admin login (from the jumpbox)

```
export VAULT_ADDR=https://10.0.0.200:8200
export VAULT_CACERT=/etc/openbao/tls/ca.crt  # copy this file over from r730xd
ROOT=$(infisical secrets get OPENBAO_ROOT_TOKEN \
  --projectId=$(jq -r .workspaceId .infisical.json) \
  --env=prod --plain --silent)
bao login "$ROOT"

# Better: mint a short-lived admin token instead of sitting on the root
bao token create -policy=lab-iac-admin -ttl=24h
```

## Policies bootstrapped

Applied by `bootstrap-openbao.yml`. Re-apply by re-running that playbook (idempotent).

| Policy | Scope |
|---|---|
| `lab-iac-admin` | Full CRUD on `secret/*`, read sys mounts/policies |
| `ansible-readonly` | Read `secret/data/lab-iac/*` |
| `ansible-readwrite` | Read/write `secret/data/lab-iac/*` |
| `prometheus-readonly` | Read `sys/metrics` only (for future scrape token) |

## Common operations

```
# Health
ssh r730xd 'systemctl is-active foundation-openbao openbao-auto-unseal'
ssh r730xd 'bao status -address=https://127.0.0.1:8200 -ca-cert=/etc/openbao/tls/ca.crt'

# Put / get a secret
bao kv put secret/lab-iac/foo my_key=my_value
bao kv get secret/lab-iac/foo

# Manual unseal (if auto-unseal failed)
ssh r730xd
bao operator unseal <key1>
bao operator unseal <key2>
bao operator unseal <key3>

# Raft snapshot on-demand
ssh r730xd 'sudo /opt/foundation/openbao/openbao-backup.sh'
```

## Gotchas learned during the 2026-04-17 deploy

Save future-you debug time — these aren't obvious from the code alone.

- **OpenBao 2.5 dropped mlock support.** Setting `disable_mlock` in HCL errors out now, and `IPC_LOCK` is not needed. Swap hardening is on the host (not in-process).
- **Container entrypoint chowns `/openbao/config` at startup.** With our read-only mount of root-owned config files, this fails. We bypass the wrapper entirely: `user: "0:0"`, `entrypoint: ["/bin/bao"]` in compose. Running as root inside the container is fine — single-tenant, host network, capability set is still tight.
- **Self-signed CA needs a CSR with `CA:TRUE`.** A bare `x509_certificate: provider=selfsigned` produces a cert with empty Subject/Issuer and no CA constraint — curl rejects with "invalid CA certificate." The role drives the CA cert through an `openssl_csr` with `basic_constraints: ['CA:TRUE']` + `key_usage: ['cRLSign', 'keyCertSign']`.
- **`bao status` exits 2 when sealed or uninitialized.** Under `set -euo pipefail`, piping through `grep` propagates the 2 and breaks `if` checks. The auto-unseal script captures the output once (`STATUS_JSON="$(bao status ... || true)"`), then inspects it without a pipe.
- **Infisical `secrets set` defaults to `--type=personal`.** Personal secrets are per-user scoped; the universal-auth machine identity on r730xd cannot read them. All playbook push calls pass `--type=shared`.
- **`secrets get` returns data with trailing whitespace.** Pipe the root token through `| trim` before passing to `bao` env vars — otherwise `bao` rejects it as "contains non-printable characters."
- **Role defaults are NOT visible to playbooks that don't apply the role.** `bootstrap-openbao.yml` and `rotate-openbao-keys.yml` load them explicitly via `vars_files`. Don't add a default like `openbao_infisical_project_id: "CHANGE_ME_..."` to role defaults if you want the vars.yml lookup to win — it won't.
- **Infisical calls `delegate_to: localhost`.** The CLI on r730xd authenticates as the machine identity; the controller (bear-desktop / jumpbox) is logged in as the operator. Run pushes/gets from the controller to use the interactive auth.
- **Audit device HCL schema is unresolved.** OpenBao 2.5 rejects the `bao audit enable` API path — config must be declarative — but the block syntax varies between docs and code. The role currently ships **without** audit enabled; a TODO comment lives in `openbao.hcl.j2`. Figure out the right block signature before the first sensitive workload depends on an audit trail.
- **`openbao_infisical_project_id` uses `lookup('env', 'PWD')`.** `playbook_dir`, `inventory_dir`, and bare relative paths all failed to locate `.infisical.json` from `group_vars/`. The `$PWD` path works because every Ansible invocation is from the repo root per README/ansible.cfg conventions. If you invoke from elsewhere, override with `-e openbao_infisical_project_id=<id>`.
- **Infisical CLI on bear-desktop is pinned at 0.38.** It works for all required subcommands but shows upgrade nags; the r730xd install is whatever the apt repo serves.

## Operational readiness checklist (per CLAUDE.md)

- [x] Health: `systemctl is-active foundation-openbao openbao-auto-unseal` + `bao status | grep Sealed: false`
- [x] Metrics: `up{job="openbao"}` via `/v1/sys/health` (unauthenticated)
- [x] Logs: Docker journald + OpenBao server logs via `docker logs foundation-openbao`
- [ ] **Audit log**: deferred (TODO — see gotcha above). Directory exists at `/mnt/zfs/foundation/openbao/audit/`, logrotate config in place — just no audit device enabled yet.
- [x] Alerts: `OpenbaoUnavailable`, `OpenbaoAutoUnsealFailed`, `OpenbaoAuditLogDiskFull` → Discord via Alertmanager
- [x] Runbooks: this file, `openbao-rotation.md`, `openbao-disaster-recovery.md`
- [x] ADR: `023-self-hosted-openbao-on-r730xd.md`
- [x] Backup: daily cron, Raft snapshot to `/mnt/zfs/foundation/openbao/backup/` (14-day retention) + ZFS snapshots of the data dir
