# ADR-022: Palworld Server Decommissioned Indefinitely

**Date:** 2026-04-17
**Status:** Accepted

## Context

Palworld ran as a systemd service on the Optiplex ("deb-web") alongside the old web-hosting workloads, with UDP 8211 forwarded from the Hetzner VPS through NetBird to the server. Earlier migration plans (`docs/migration-2026/migration-plan.md` Phase 3B) called for containerizing it and moving it into K8s or a VM.

Two things now point the other way:

- The Optiplex has been fully repurposed as a K8s worker. There's no longer a "deb-web" host to keep the service running on.
- The operator isn't actively playing; rebuilding the service into K8s or a VM would be work for a workload nobody is using.

Save data (52 MB) and config were backed up to `~/Backups/deb-web/` on 2026-04-03 during the deb-web cleanup.

## Decision

**Decommission the Palworld server indefinitely.** Don't migrate it to K8s, don't move it to the R730xd, don't keep a VM running for it. The backup is preserved — if we ever want it back, the path is: spin up a server (any host with Steam + SteamCMD), restore the save, update DNS / the UDP forward.

## Consequences

- `netbird_palworld_ip` and the `udp_forwarding_rules` entry for port 8211 get removed from `ansible/inventory/proxy-vps.yml` and `ansible/group_vars/all/network.yml`.
- Any references to "Palworld migration" in `docs/migration-2026/` get removed or rewritten to point here.
- `archive/palworld-udp-forwarding.md` stays as the historical record of how the UDP forward was wired up, in case it's ever rebuilt.
- `feedback_iac_and_docs.md` (auto-memory) continues to reference the "manual changes to Palworld config got wiped" incident as a lesson — that lesson is about IaC discipline, not about Palworld, and the example is still valid.
- No migration work needed to close this out beyond the Ansible / doc edits landing with this ADR.

## References

- Backup location: `~/Backups/deb-web/` (save data + config, 52 MB).
- `archive/palworld-udp-forwarding.md` — original setup notes.
- `ansible/inventory/proxy-vps.yml` — UDP forwarding rule being removed.
- `ansible/group_vars/all/network.yml` — `netbird_palworld_ip` being removed.
