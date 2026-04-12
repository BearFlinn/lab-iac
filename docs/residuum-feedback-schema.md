# Residuum Feedback — Database Schema Workshop

Starting point for the Postgres schema and provisioning work for the residuum feedback ingestion feature. See `residuum-feedback-plan.md` for the broader lab-side plan and the cross-cutting architectural decisions at `~/Projects/residuum-feedback-decisions.md`.

This is a **workshop doc, not a spec.** The schema is not locked. What's captured here:

- What data needs to be stored
- The design goals the schema must satisfy
- A proposed starting sketch
- Open questions to resolve before migrations are written
- Things that are already locked and shouldn't be re-litigated

---

## Purpose

The new `feedback-ingest` service needs a Postgres database in the lab to store bug report and feedback submission metadata. This database must be:

- **Dedicated** to the feature — separate from any other lab-data database, so backups, versioning, and future migrations move independently
- **Normalized** — built to support analysis and investigation tooling, not just write-once logging
- **Isolated** on the existing `r730xd-postgres` instance under a new database and a scoped role
- **Write-oriented now, query-oriented later** — the first pass is write-only from the ingest service, but the schema must not box out the read API / investigation UI that'll be built on top

Trace data lives in Tempo under the dedicated `residuum-reports` tenant. Postgres stores only metadata, with `trace_id` as the join key back into Tempo.

---

## What needs to be stored

### Shared across both kinds

Every report has:

- Internal report ID — UUID v7 (time-sortable under the hood)
- Public-facing report ID — `RR-` + 10-char Crockford base32, shown to the user
- Kind — `bug` or `feedback`
- Created-at timestamp
- Submitter IP — for rate-limit analytics and abuse detection (**not** for display)
- Residuum version
- Residuum commit (nullable — not every build captures it)
- Triage status — one of `new`, `triaged`, `investigating`, `resolved`, `wontfix`
- Developer notes (nullable; populated during triage, not at submission)
- Tempo tenant name (nullable; only populated when traces are attached)
- Trace ID (nullable; only populated when traces are attached)

### Bug-report-only

User-typed, always present:

- `what_happened` — required free text
- `what_expected` — required free text
- `what_doing` — required free text
- `severity` — enum: `crash`, `wrong_output`, `confusing`, `slow`

Client context captured at submission:

- OS (e.g. `linux`, `darwin`, `windows`)
- Arch (e.g. `x86_64`, `aarch64`)
- Model provider (e.g. `anthropic`) — nullable
- Model name (e.g. `claude-opus-4-6`) — nullable

Variable-arity snapshots:

- **Active subagents** — zero-to-many `{name, status}` entries, per-report, never updated after submission
- **Config flags** — zero-to-many `{key, value}` entries from a pre-curated allowlist of configuration toggles, per-report, never updated

### Feedback-only

- `message` — required free text
- `category` — nullable free text or short enum

Feedback carries **no** client-context fields beyond the shared `version` on the parent. No OS, no arch, no subagent snapshot, no config flags. This is intentional — feedback is low-overhead by design. "This thing is confusing" doesn't need a full data dump.

### Explicitly NOT stored

The schema has no columns for any of these, and shouldn't grow them later without a deliberate decision:

- Chat history, conversation turns, agent transcripts
- Memory or file contents
- API keys, tokens, credentials of any kind
- File paths or directory listings
- Anything derived from the user's disk state

These are excluded at the client (residuum) layer before the payload is ever sent. Sanitization of the attached span dump is forced-on regardless of the user's global sanitize setting; free-text fields the user typed themselves are not redacted (users are responsible for keeping PII out of what they write).

---

## Design goals

1. **Normalized.** No JSONB catch-all columns for structured data. Variable-arity snapshots (subagents, config flags) live in their own tables.
2. **Class-table inheritance.** One parent `reports` table for shared identity; separate child tables for the kind-specific shape. The parent's `kind` column is authoritative.
3. **Queryable from day one.** Indexes that support the future investigation tooling: list by kind, filter by status, look up by public ID, trace ID.
4. **Cascades on delete.** Deleting a parent report cleans up all children in one statement.
5. **Postgres-native constraints.** `CHECK` constraints on enum-shaped columns rather than PG `ENUM` types, so adding a new value is a simple DDL change.
6. **Forward-compatible.** The read API is deferred, but the schema must not paint us into a corner.

---

## Proposed sketch (starting point)

```sql
-- Parent: shared identity + triage state
CREATE TABLE reports (
  id              uuid PRIMARY KEY,           -- UUID v7 internally
  public_id       text UNIQUE NOT NULL,       -- user-facing RR-XXXXXXXXXX
  kind            text NOT NULL
                    CHECK (kind IN ('bug', 'feedback')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  submitter_ip    inet,
  version         text NOT NULL,
  commit          text,
  status          text NOT NULL DEFAULT 'new'
                    CHECK (status IN ('new','triaged','investigating','resolved','wontfix')),
  notes           text,
  trace_id        text,
  tempo_tenant    text
);

-- Bug-only: user-typed fields + inline client context
CREATE TABLE bug_reports (
  report_id       uuid PRIMARY KEY
                    REFERENCES reports(id) ON DELETE CASCADE,
  what_happened   text NOT NULL,
  what_expected   text NOT NULL,
  what_doing      text NOT NULL,
  severity        text NOT NULL
                    CHECK (severity IN ('crash','wrong_output','confusing','slow')),
  os              text NOT NULL,
  arch            text NOT NULL,
  model_provider  text,
  model_name      text
);

-- Bug-only: variable-arity subagent snapshot
CREATE TABLE bug_report_active_subagents (
  report_id  uuid NOT NULL
               REFERENCES reports(id) ON DELETE CASCADE,
  name       text NOT NULL,
  status     text NOT NULL,
  PRIMARY KEY (report_id, name)
);

-- Bug-only: variable-arity config toggle snapshot
CREATE TABLE bug_report_config_flags (
  report_id  uuid NOT NULL
               REFERENCES reports(id) ON DELETE CASCADE,
  key        text NOT NULL,
  value      text NOT NULL,
  PRIMARY KEY (report_id, key)
);

-- Feedback-only: minimal
CREATE TABLE feedback_reports (
  report_id  uuid PRIMARY KEY
               REFERENCES reports(id) ON DELETE CASCADE,
  category   text,
  message    text NOT NULL
);

-- Indexes supporting the future investigation tooling
CREATE INDEX reports_created_at_idx   ON reports (created_at DESC);
CREATE INDEX reports_kind_created_idx ON reports (kind, created_at DESC);
CREATE INDEX reports_status_idx       ON reports (status);
CREATE INDEX reports_trace_id_idx     ON reports (trace_id)
                                      WHERE trace_id IS NOT NULL;
CREATE INDEX bug_reports_severity_idx ON bug_reports (severity);
```

Notable choices in this sketch:

- **`public_id` is a dedicated column**, not derived at query time. Stable, indexable, rotatable independently of the internal UUID.
- **Client context is inline on `bug_reports`**, not a separate `bug_client_context` table. A 1:1 split would be pure normalization ritual with no integrity or lifecycle benefit.
- **`feedback_reports` has only three columns.** Everything else feedback needs (version, created_at, status) lives on the parent.
- **`CHECK` constraints instead of PG `ENUM`** — adding a new severity or status is a column-level migration, not an `ALTER TYPE` dance.
- **Partial index on `trace_id`** because it's nullable and every feedback row will be null there — no point indexing them.

---

## Provisioning

The feedback database lives on the existing `r730xd-postgres` instance. Additions to the `r730xd-postgres` Ansible role:

- A new database (name TBD — `residuum_reports` is the working placeholder)
- A scoped role with only the permissions it needs on that database — `SELECT`/`INSERT`/`UPDATE` on the report tables for the ingest service, no access to any other database in the instance
- Role password stored in `group_vars/all/vault.yml`
- Database connection string assembled into `FEEDBACK_DATABASE_URL` and surfaced to the K8s Secret consumed by `feedback-ingest`

Migrations are run from the `feedback-ingest` service itself via `sqlx migrate` on startup, matching the pattern the relay already uses. This keeps schema evolution in the service's own repo alongside the code that depends on it, and avoids an out-of-band Ansible step every time the schema changes.

---

## Open questions

Need to be resolved before migrations are written:

1. **Database name.** `residuum_reports` is a placeholder — confirm or rename in line with naming patterns elsewhere on the instance.

2. **Snapshots: normalized tables or JSONB columns?** The argument for tables is genuine queryability ("show me all reports where subagent X was running"). The argument for JSONB is simpler shape, faster inserts, no orphan risk. Leaning tables because the investigation tooling is the entire point of this work, but worth a deliberate call.

3. **Any third variable-arity thing to normalize the same way?** E.g., environment variables, loaded MCP servers, enabled feature flags. The allowlist of what gets auto-attached is still TBD on the residuum side — once that list is pinned, decide whether any of it belongs in its own child table.

4. **Retention policy.** How long are reports kept? Indefinitely? 1 year? Does retention need to match the Tempo `residuum-reports` tenant's block retention (currently `720h` / 30 days per the `r730xd-tempo` role)? If Postgres outlives Tempo, `trace_id` becomes a dangling reference after 30 days — is that OK, or should metadata be purged in lockstep?

5. **Indexes on the snapshot tables.** Do we need a reverse index (`name → report_id`, `key → report_id`) to support "which reports had subagent X active" questions? Probably yes if the investigation tooling wants them, but not strictly needed for writes.

6. **Audit trail on `status` and `notes`.** When status changes or notes are updated during triage, do we want a history table, or is the current state enough? Leaning sufficient for the first pass; history can be added later without a breaking change.

7. **Submitter IP retention.** `submitter_ip inet` is useful for rate-limit analytics and abuse forensics, but it's the most PII-adjacent field in the schema. Drop it after N days? Hash it at insertion? Leave it raw? Needs a deliberate call, especially if the read API eventually surfaces it.

8. **Migrations toolchain.** Confirm `sqlx migrate` is the right fit vs. something like `refinery` or `dbmate`. Matching the existing relay is the strongest argument.

9. **Seed / fixture data.** When someone runs `feedback-ingest` locally against a test Postgres, what's the bootstrap? Probably just empty migrations; no seed rows needed.

---

## Things that are NOT open

Locked by decisions already made elsewhere; should not be re-litigated during the schema workshop:

- The two kinds (`bug`, `feedback`) and their distinct shape
- The required fields on bug reports (`what_happened`, `what_expected`, `what_doing`, `severity`)
- The feedback minimalism (message + optional category + version only)
- The `RR-XXXXXXXXXX` public ID format
- The `residuum-reports` Tempo tenant name
- The exclusion of chat history, memory, file contents, secrets from any column
- The choice to run on the existing `r730xd-postgres` instance (not a separate PG server)
- Storage isolation: dedicated database, not a schema inside an existing database
