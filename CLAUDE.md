# lab-iac

Homelab Infrastructure as Code. See `README.md` for architecture, machines, repo structure, and common commands. See `docs/migration-2026/` for migration plan and hardware inventory.

# Secrets Management

- **Ansible Vault:** `group_vars/all/vault.yml` encrypted, decrypted via `.vault_pass` file
- **Vault password file:** Must exist at repo root, git-ignored
- Secrets must never appear in plaintext in IaC — use `no_log: true` for tasks that handle sensitive values

# Rules

- All configuration and infrastructure MUST be conducted with IaC. Manual changes must be clearly documented.
- **Done means deployed.** Writing IaC is not the finish line — run the playbook, verify it works, then report completion. Never stop at "here's the code I wrote."
- Warnings are blockers. Resolve before considering work complete. If a warning truly cannot be resolved, document why.
- Decision records: When a non-obvious choice is made, write an ADR in `docs/decisions/` (use `/adr` skill).

# Operational Readiness Checklist

Every service, machine, or infrastructure component stood up during the migration MUST have answers to the following before it is considered complete. If a question doesn't apply, document why.

## Observability
- **Health signal:** How do we know this is working right now? (e.g., systemd status, HTTP health endpoint, kubectl readiness probe, process check)
- **Metrics:** What should be measured? (e.g., disk usage, request latency, queue depth, CPU/memory) Where do metrics go?
- **Logs:** Where do logs live? Are they rotated? Can they be searched? (e.g., journald, file path, stdout to container runtime)

## Alerting
- **Failure detection:** How do we know when this breaks? What specifically triggers an alert? (e.g., service down, disk >90%, cert expiring, backup failed)
- **Alert destination:** Where do alerts go? (e.g., Ntfy, email, Slack, dashboard, UPS shutdown signal)
- **On-call response:** Who or what acts on the alert? Is there a runbook or is the fix obvious?

## Troubleshooting
- **First steps:** If this is down, what do you check first? (e.g., `systemctl status X`, `kubectl logs`, check upstream dependency)
- **Dependencies:** What does this depend on? What depends on this? (e.g., NFS requires R730xd network, K8s pods require NFS)
- **Common failure modes:** What's most likely to go wrong? (e.g., disk full, OOM, network unreachable, cert expired, DNS)
- **Recovery:** How do you restart or rebuild this? Is it automatic (systemd restart, K8s reschedule) or manual?

## Documentation
- **Decision record:** If a non-obvious choice was made, is there an ADR in `docs/decisions/`? (Use `/adr` skill)
- **Runbook:** For anything that requires multi-step recovery, is there a runbook?

When writing Ansible roles, scripts, or configs — if the operational story isn't addressed in the IaC itself (e.g., monitoring agent installed, health check configured, log rotation set up), flag it as a TODO or open question rather than silently skipping it.
