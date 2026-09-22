# System Vocabulary and Core Concepts (`CONTEXT.md`)

This document defines the foundational vocabulary, architectural invariants, and operational mechanics of the **Universal Herdr Swarm** (`herd-swarm`). 

All human operators, orchestrators (`looper`), implementation agents (`arch`), and review agents (`pm`, `reviewer`) must adhere to these definitions and strictly heed the associated **_Avoid_** warnings.

---

## Core System Vocabulary

### 1. Fail-Closed
The foundational security and correctness invariant requiring that any missing dependency, unconfigured Git remote, unverified test suite, unauthenticated CLI, or failed verification gate halts execution with a non-zero exit code (`1`) rather than making permissive assumptions or substituting synthetic mocks.
- **Implementation**: [`lib/profile.sh`](lib/profile.sh), [`lib/preflight.sh`](lib/preflight.sh), [ADR 0001](docs/adr/0001-fail-closed-profile-and-test-gating.md).
- **_Avoid_**: _Avoid_ falling back to default foreign repositories (such as `Standard-Pentest/kultivait`), synthetic test bypasses (`TEST_CMD="true"`), or silently caching empty/unrunnable test commands. Never allow autonomous modes to run without positive confirmation of a real test suite.

### 2. Nonce Delivery
The communication protocol where extensive agent instructions and standing briefs (3–10 KB) are compiled from templates into local files (`.herdr-swarm/briefs/<seat>.md`) on disk, and delivered to the agent's Herdr terminal via an ultra-compact (<200 bytes) reference prompt followed by a synthetic enter keystroke.
- **Implementation**: [`lib/briefs.sh`](lib/briefs.sh), [ADR 0003](docs/adr/0003-dynamic-seating-and-nonce-brief-delivery.md).
- **_Avoid_**: _Avoid_ dumping raw markdown brief contents directly into the Herdr terminal or prompt command (e.g. `cat "$brief_file" | herdr agent prompt`), which saturates the PTY input buffer, truncates instructions, corrupts terminal escape sequences, and drops prompt submissions.

### 3. Seat Ledger
The durable, machine-readable JSON record stored at `.herdr-swarm/seats.json` capturing the active workspace ID and the exact mapping of every seated agent to its allocated pane ID and runtime engine kind.
- **Implementation**: `.herdr-swarm/seats.json` (runtime state, per target repo), [`lib/lifecycle.sh`](lib/lifecycle.sh), [ADR 0004](docs/adr/0004-safe-workspace-lifecycle-and-seat-ledger.md).
- **_Avoid_**: _Avoid_ relying on ambient environment variables (`$HERDR_WORKSPACE_ID`), terminal focus, or fuzzy workspace searches during teardown; _Avoid_ closing panes indiscriminately, which kills active human shells, dev servers, and unrecorded operator tabs.

### 4. Slug Namespacing
The deterministic identifier transformation (`seat-<slug>`, e.g. `arch-kultivait`, `looper-hinchk-stampede`) ensuring that all seated agents are unique in Herdr's server-global agent registry while strictly satisfying the name grammar `^[a-z][a-z0-9_-]*$`.
- **Implementation**: `slugify()` in [`lib/common.sh`](lib/common.sh), [`lib/config.sh`](lib/config.sh), [ADR 0003](docs/adr/0003-dynamic-seating-and-nonce-brief-delivery.md).
- **_Avoid_**: _Avoid_ bare seat names (`arch`, `pm`, `looper`) which collide across projects in Herdr; _Avoid_ illegal separator characters such as unicode middle dots (`·`), spaces, dots, colons, or uppercase characters that trigger Herdr agent registration errors.

### 5. Suite Gate
The automated execution of the target repository's verified test suite command (`TEST_CMD`), initiated by the supervisor daemon upon detecting an agent completion signal, serving as the mandatory quality boundary for all code changes before a ticket can be retired.
- **Implementation**: [`loop-bot-herd.sh`](loop-bot-herd.sh), [`lib/profile.sh`](lib/profile.sh), [ADR 0001](docs/adr/0001-fail-closed-profile-and-test-gating.md).
- **_Avoid_**: _Avoid_ accepting an agent's conversational claim of completion ("I ran the tests and they pass!") without an independent supervisor suite gate run; _Avoid_ synthetic, unrunnable, or no-op test commands (`true`, `none`, empty string).

### 6. Wayfinder Map
The living, human- and agent-readable markdown artifact (`maps/universal-herdr-swarm.md` and associated `maps/tickets/*.md`) that serves as the single architectural compass, recording project destinations, immutable invariants, accepted decisions, and discrete task tickets with mandatory 3-line preambles.
- **Implementation**: [`maps/universal-herdr-swarm.md`](maps/universal-herdr-swarm.md), [`maps/tickets/`](maps/tickets).
- **_Avoid_**: _Avoid_ undocumented architectural drift, tribal knowledge, untracked changes, or executing tasks that lack explicit Intended Outcome, Done-Criteria, and Verification Step definitions.

### 7. Supervisor Gate
The autonomous supervisor daemon (`loop-bot-herd.sh`) that harvests worker verdict emissions (`ARCH DONE #<ticket> <sha>`), applies exact-match `(ticket, sha)` deduplication via `jq`, triggers the Suite Gate, records structured JSONL verdicts, and alerts the orchestrator.
- **Implementation**: [`loop-bot-herd.sh`](loop-bot-herd.sh), [ADR 0002](docs/adr/0002-exact-sha-supervisor-deduplication.md).
- **_Avoid_**: _Avoid_ naive substring grepping over verdict logs (which mistakenly treats `#23` as `#230`); _Avoid_ permanent ticket lockout on `RED` (failed) verdicts, which prevents agents from submitting new commit SHAs under the fix-and-reverdict protocol.

---

## Architectural Interaction Matrix

```
                      ┌────────────────────────┐
                      │  swarm.config.toml     │
                      │  (Registry of Seats)   │
                      └───────────┬────────────┘
                                  │
                                  ▼
┌──────────────────┐    ┌────────────────────┐    ┌──────────────────────┐
│  Preflight Gate  ├───>│  Dynamic Seating   ├───>│ Nonce Brief Delivery │
│ (9-Point Matrix) │    │ (Slug Namespacing) │    │  (<200b Pointer)     │
└──────────────────┘    └─────────┬──────────┘    └──────────────────────┘
                                  │
                                  ▼
                        ┌───────────────────┐
                        │    Seat Ledger    │
                        │   (seats.json)    │
                        └─────────┬─────────┘
                                  │
                                  ▼
                        ┌───────────────────┐
                        │ Seat Verification │
                        │  (Readiness Gate) │
                        └─────────┬─────────┘
                                  │
                                  ▼
┌──────────────────┐    ┌───────────────────┐    ┌──────────────────────┐
│  Wayfinder Map   │<───│  Worker Execution │───>│   Supervisor Gate    │
│ (Local Tickets)  │    │  (arch / looper)  │    │ (Exact-SHA Dedupe)   │
└──────────────────┘    └───────────────────┘    └──────────┬───────────┘
                                                            │
                                                            ▼
                                                 ┌──────────────────────┐
                                                 │      Suite Gate      │
                                                 │ (Fail-Closed Test)   │
                                                 └──────────────────────┘
```

---

## Key Invariants & Safety Protocols

1. **Role Separation**: `looper` orchestrates and verifies; implementation code is authored exclusively by `arch`.
2. **Git Remote Safety**: Remote git operations (`push`, release tags) require explicit human driver approval.
3. **Workspace Discipline**: Pane routing must always address explicit workspace-prefixed IDs (`wX:pY`) obtained from tab anchors; scripts must **never** use `--current`.
4. **Prompt Maturity**: All task assignments and kickoff directives must explicitly state **Intended Outcome**, **Explicit Done-Criteria**, and **Verification Step**.
