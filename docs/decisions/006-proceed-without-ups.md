# ADR-006: Proceed Without UPS

**Date:** 2026-04-02
**Status:** Accepted (revisit after battery replacement)

## Context

The APC Back-UPS RS 1500 has dead batteries that no longer hold a charge. Replacing them is not blocking any migration work. Additionally, the R730xd and Quanta (likely) require pure sine wave output — the APC RS 1500 produces simulated sine wave, so servers can't use it regardless.

## Decision

Proceed with the migration without UPS protection. Replace batteries later as a separate task.

## Alternatives Considered

- **Delay migration until batteries replaced** — Unnecessary. The risk of power loss during migration is low and the cost of delay is high.
- **Buy a new pure sine wave UPS** — Out of scope/budget for now. Can revisit after migration is complete and power draw is measured.

## Consequences

- **No graceful shutdown on power loss.** ZFS (with its copy-on-write design) and ext4 journaling provide filesystem-level protection, but in-flight writes may be lost.
- **No ride-through for brief outages.** Even a momentary flicker will reboot everything.
- **Reduced scope.** Even with working batteries, the APC RS 1500 (865W, simulated sine) could only protect consumer-PSU machines (Inspiron, Optiplex, Tower PC, switch). Servers would need a separate pure sine UPS.
- **Revisit after migration.** Once power draw is measured in the closet, right-size a UPS purchase (pure sine for servers, existing APC with new batteries for consumer machines).
