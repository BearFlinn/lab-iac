# ADR-009: Start With AP230 Only for WiFi

**Date:** 2026-04-02
**Status:** Accepted

## Context

Three Aerohive APs are available: 1× AP230 (3×3:3 MIMO, higher performance) and 2× AP130 (lower end, one has older firmware and a bad NAND block). All three are confirmed working in standalone mode. The question is whether to deploy all three at once or start with one and assess coverage.

## Decision

Deploy the AP230 first as the sole WiFi AP. Add AP130s only if coverage testing reveals dead spots.

## Alternatives Considered

- **Deploy all three at once** — More upfront work (3 cable runs, 3 configs, 3 mounts) without knowing if coverage is actually insufficient. The AP230's 3×3:3 MIMO may cover the entire house on its own.

## Consequences

- **Less work upfront.** One cable run, one config, one mount point.
- **Coverage may be sufficient.** The AP230 is the highest-performance unit. If it covers the house, the AP130s become spares.
- **Easy to expand.** If dead spots are found, AP130s can be added incrementally — SR2024 has plenty of PoE ports.
