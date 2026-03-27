---
name: adr
description: Create or update Architectural Decision Records in docs/decisions/. Use when a non-obvious infrastructure decision is made, when the user says "let's document why", when reviewing work and a "why" is missing, or when the user invokes /adr. Also suggest proactively when a decision is made that future-self would question — e.g., choosing one storage backend over another, picking a network topology, deciding what to expose vs keep internal, or choosing to skip something.
---

# Architectural Decision Records

ADRs capture the *why* behind infrastructure decisions. They live in `docs/decisions/` and are numbered sequentially.

## When to Write an ADR

- A technology or approach was chosen over alternatives
- A tradeoff was accepted (e.g., convenience vs security, simplicity vs flexibility)
- Something was intentionally *not* done (and the reason isn't obvious)
- A constraint forced a specific decision (hardware limitation, budget, compatibility)
- Future-you would ask "why did we do it this way?"

Do NOT write ADRs for obvious choices (e.g., "we chose Debian because it's stable") unless there's a non-obvious constraint behind it.

## Format

File naming: `NNNN-short-title.md` (e.g., `0001-mergerfs-over-zfs-for-storage.md`)

To determine the next number, list existing files in `docs/decisions/`.

```markdown
# NNNN: Short Decision Title

**Date:** YYYY-MM-DD
**Status:** accepted | superseded by NNNN | deprecated

## Context

What situation or problem prompted this decision? What constraints exist?
Keep it to 2-4 sentences. Include the specific machines, services, or components involved.

## Decision

What was decided? Be specific — name the tool, config, topology, or approach.
1-3 sentences.

## Alternatives Considered

- **Alternative A** — Why it was rejected (1 sentence)
- **Alternative B** — Why it was rejected (1 sentence)

Only include alternatives that were genuinely considered. Skip this section if there was really only one viable option (but explain why in Context).

## Consequences

What follows from this decision? Include both positive and negative.

- What gets easier or better
- What gets harder or is now a limitation
- What future decisions this constrains or enables
```

## Process

1. Check `docs/decisions/` for existing ADRs — avoid duplicates, and reference related ADRs.
2. Determine the next number.
3. Write the ADR using the format above. Be concise — an ADR should be readable in under 60 seconds.
4. If this decision supersedes a previous one, update the old ADR's status to `superseded by NNNN`.

## Proactive Suggestions

When working on infrastructure in this repo, suggest an ADR when:
- The user picks one approach over another and explains their reasoning verbally
- A decision is made that isn't self-evident from the IaC
- Something is configured in a way that looks wrong but is intentional
- A workaround is implemented due to a hardware or software limitation
