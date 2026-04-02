# ADR-007: 3TB Data Drive Mounted Directly Into MergerFS Pool

**Date:** 2026-04-02
**Status:** Accepted

## Context

One of the 5×3TB drives (R730xd bay 8) contained existing data from the mini PC that needed to be preserved. The migration plan originally called for backing up this data to a separate location before the drive could be reformatted and added to the MergerFS pool. This was marked as a hard blocker for all storage work.

## Decision

Mount the 3TB data drive directly into the MergerFS pool as-is, preserving the existing data in place. No separate backup step needed.

## Alternatives Considered

- **Back up to external storage first, then reformat** — Slower, requires spare storage capacity, and adds a data-copy step. Unnecessary since MergerFS can merge an existing filesystem into the pool without reformatting.

## Consequences

- **Unblocked storage work immediately.** Removed the biggest Phase 0 blocker — all 7 drives are installed and the pool is operational.
- **Data is now protected by SnapRAID parity.** The 2×4TB parity drives protect against single or double drive failure, which is better protection than the data had on the standalone mini PC.
- **Directory structure preserved.** The existing files are accessible at their original paths within the MergerFS mount. No reorganization was needed.
