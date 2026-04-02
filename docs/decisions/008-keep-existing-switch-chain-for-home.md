# ADR-008: Keep Existing Switch Chain for Home Network

**Date:** 2026-04-02
**Status:** Accepted

## Context

The original migration plan called for running new cable from the closet to the master bedroom and garage, replacing the daisy-chained consumer switches (basement 5-port → room 5-port managed → 8-port unmanaged) with direct runs to the SR2024. This would clean up the topology but requires significant cabling effort for non-lab traffic that works fine today.

## Decision

Keep the existing switch chain for home network drops (bedroom, garage). Only run new cable for AP placement. Lab machines connect directly to the SR2024 in the closet.

## Alternatives Considered

- **Replace entire switch chain with SR2024 home runs** — Cleaner topology but high effort for low return. The existing chain serves non-lab devices that don't need managed switching or high reliability.

## Consequences

- **Less cabling work.** Only AP cable runs are needed, not full house re-wiring.
- **Home network remains daisy-chained.** A switch failure in the chain still kills downstream devices, but these are non-critical (bedroom, garage).
- **Lab network is clean.** All lab machines go directly to the SR2024 — the switch chain is isolated to home traffic.
- **Can revisit later.** If the chain becomes a problem, running new cable to the SR2024 is always an option.
